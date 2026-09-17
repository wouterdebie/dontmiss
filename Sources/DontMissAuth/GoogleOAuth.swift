import AppKit
import Foundation

@MainActor
public final class GoogleOAuth {
    private struct TokenResponse: Decodable, Sendable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
        let scope: String?
        let token_type: String
    }
    private var access: String?
    private var expires = Date.distantPast
    private var activeListener: LoopbackListener?
    private var signingIn = false
    private var disconnecting = false
    private var generation = 0
    private var refreshTask: Task<String, Error>?
    private let session: URLSession
    private let credentialKey: String

    public convenience init() { self.init(credentialKey: "refresh-token") }

    init(credentialKey: String) {
        self.credentialKey = credentialKey
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    public func hasCredentials() throws -> Bool { try KeychainStore.read(credentialKey) != nil }
    public func hasClientConfiguration() throws -> Bool { try KeychainStore.read("client") != nil }

    public func importClientConfiguration(from url: URL) throws {
        guard !signingIn, !disconnecting, try !hasCredentials() else {
            throw OAuthError.configuration("Disconnect before importing another OAuth client.")
        }
        let configuration = try ClientConfiguration.parse(Data(contentsOf: url))
        try KeychainStore.write(JSONEncoder().encode(configuration), account: "client")
    }

    private func configuration() throws -> ClientConfiguration {
        guard let data = try KeychainStore.read("client") else {
            throw OAuthError.configuration("Import your Google Desktop OAuth client JSON first.")
        }
        return try JSONDecoder().decode(ClientConfiguration.self, from: data)
    }

    public func signIn() async throws {
        guard !signingIn, !disconnecting else { throw OAuthError.busy }
        signingIn = true
        generation += 1
        let currentGeneration = generation
        defer {
            signingIn = false
            activeListener?.cancel()
            activeListener = nil
        }
        let state = try OAuthSupport.random()
        let callbackListener = LoopbackListener(state: state)
        activeListener = callbackListener
        try await withTaskCancellationHandler {
            let client = try configuration()
            let verifier = try OAuthSupport.random()
            let redirect = try await callbackListener.start()
            guard currentGeneration == generation else { throw OAuthError.cancelled }
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: client.clientID),
                URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: OAuthSupport.scopes.joined(separator: " ")),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: OAuthSupport.challenge(verifier)),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "select_account consent")
            ]
            guard let url = components.url, NSWorkspace.shared.open(url) else { throw OAuthError.browser }
            let code = try await callbackListener.code()
            guard currentGeneration == generation else { throw OAuthError.cancelled }
            let token = try await requestToken([
                "client_id": client.clientID, "client_secret": client.clientSecret,
                "code": code, "code_verifier": verifier,
                "redirect_uri": redirect.absoluteString, "grant_type": "authorization_code"
            ])
            guard currentGeneration == generation else { throw OAuthError.cancelled }
            guard let granted = token.scope,
                  Set(OAuthSupport.scopes).isSubset(of: Set(granted.split(separator: " ").map(String.init))) else {
                throw OAuthError.missingScopes
            }
            guard let refresh = token.refresh_token, !refresh.isEmpty else { throw OAuthError.invalidResponse }
            try KeychainStore.write(Data(refresh.utf8), account: credentialKey)
            cache(token)
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelSignIn() }
        }
    }

    public func cancelSignIn() {
        guard signingIn else { return }
        generation += 1
        activeListener?.cancel()
    }

    public func accessToken() async throws -> String {
        if let access, expires > Date().addingTimeInterval(60) { return access }
        if let refreshTask { return try await refreshTask.value }
        let currentGeneration = generation
        let task = Task { @MainActor in
            let client = try configuration()
            guard let data = try KeychainStore.read(credentialKey),
                  let refresh = String(data: data, encoding: .utf8), !refresh.isEmpty else {
                throw OAuthError.notConnected
            }
            let token = try await requestToken([
                "client_id": client.clientID, "client_secret": client.clientSecret,
                "refresh_token": refresh, "grant_type": "refresh_token"
            ])
            guard generation == currentGeneration else { throw OAuthError.cancelled }
            if let replacement = token.refresh_token, !replacement.isEmpty {
                try KeychainStore.write(Data(replacement.utf8), account: credentialKey)
            }
            cache(token)
            return token.access_token
        }
        refreshTask = task
        defer {
            if generation == currentGeneration { refreshTask = nil }
        }
        return try await task.value
    }

    public func disconnect() async throws {
        guard !disconnecting else { throw OAuthError.busy }
        disconnecting = true
        defer { disconnecting = false }
        generation += 1
        activeListener?.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        access = nil
        expires = .distantPast
        let token = try KeychainStore.read(credentialKey)
        try KeychainStore.remove(credentialKey)
        guard let token, let text = String(data: token, encoding: .utf8) else { return }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthSupport.form(["token": text])
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw OAuthError.revocation
            }
        } catch { throw OAuthError.revocation }
    }

    func invalidateCachedToken() {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        access = nil
        expires = .distantPast
    }

    private func cache(_ response: TokenResponse) {
        access = response.access_token
        expires = Date().addingTimeInterval(response.expires_in)
    }

    private func requestToken(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthSupport.form(fields)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OAuthError.invalidResponse }
        if http.statusCode != 200 {
            struct Failure: Decodable { let error: String }
            if let failure = try? JSONDecoder().decode(Failure.self, from: data), failure.error == "invalid_grant" {
                throw OAuthError.reconnect
            }
            throw OAuthError.response(http.statusCode)
        }
        let token: TokenResponse
        do { token = try JSONDecoder().decode(TokenResponse.self, from: data) }
        catch { throw OAuthError.invalidResponse }
        guard !token.access_token.isEmpty, token.expires_in > 0,
              token.token_type.lowercased() == "bearer" else { throw OAuthError.invalidResponse }
        return token
    }
}
