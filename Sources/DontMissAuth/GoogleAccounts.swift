import Foundation
import CryptoKit

public struct GoogleAccount: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var label: String { id }
    public init(id: String) { self.id = id }
}

struct AccountIndex: Codable {
    var accounts: [GoogleAccount] = []

    mutating func add(_ account: GoogleAccount) {
        if !accounts.contains(where: { $0.id == account.id }) { accounts.append(account) }
        accounts.sort { $0.id < $1.id }
    }

    static func credentialKey(_ id: String) -> String {
        "account-" + OAuthSupport.base64URL(Data(SHA256.hash(data: Data(id.utf8))))
    }
}

@MainActor
public final class GoogleAccounts {
    private let legacy = GoogleOAuth()
    private let pending = GoogleOAuth(credentialKey: "pending-account")
    private var clients: [String: GoogleOAuth] = [:]
    private var changingAccounts = false
    private var signInVersion = 0

    public init() {}

    public func hasClientConfiguration() throws -> Bool { try legacy.hasClientConfiguration() }
    public func hasCredentials() throws -> Bool { try !accounts().isEmpty || legacy.hasCredentials() }
    public func accounts() throws -> [GoogleAccount] { try index().accounts }

    public func importClientConfiguration(from url: URL) throws {
        guard !changingAccounts, try !hasCredentials() else {
            throw OAuthError.configuration("Disconnect all Google accounts before replacing the OAuth client.")
        }
        try legacy.importClientConfiguration(from: url)
    }

    public func restoreAccounts() async throws -> [GoogleAccount] {
        guard try legacy.hasCredentials() else { return try accounts() }
        guard !changingAccounts else { throw OAuthError.busy }
        changingAccounts = true
        defer { changingAccounts = false }
        let account = try await identify(using: legacy)
        try transferCredential(from: "refresh-token", to: account)
        return try accounts()
    }

    public func signIn() async throws -> GoogleAccount {
        guard !changingAccounts else { throw OAuthError.busy }
        changingAccounts = true
        signInVersion += 1
        let version = signInVersion
        defer { changingAccounts = false }
        try await pending.signIn()
        let account = try await identify(using: pending)
        guard version == signInVersion else { throw OAuthError.cancelled }
        try Task.checkCancellation()
        try transferCredential(from: "pending-account", to: account)
        return account
    }

    public func cancelSignIn() {
        signInVersion += 1
        pending.cancelSignIn()
    }

    public func accessToken(for accountID: String) async throws -> String {
        guard try accounts().contains(where: { $0.id == accountID }) else { throw OAuthError.notConnected }
        return try await client(for: accountID).accessToken()
    }

    public func disconnect(_ accountID: String) async throws {
        guard !changingAccounts else { throw OAuthError.busy }
        changingAccounts = true
        defer { changingAccounts = false }
        let client = client(for: accountID)
        var revocationError: Error?
        do { try await client.disconnect() }
        catch { revocationError = error }
        // Keep the account visible if Keychain itself prevented credential removal.
        if try !client.hasCredentials() {
            var current = try index()
            current.accounts.removeAll { $0.id == accountID }
            try save(current)
            clients.removeValue(forKey: accountID)
        }
        if let revocationError { throw revocationError }
    }

    private func client(for id: String) -> GoogleOAuth {
        if let client = clients[id] { return client }
        let client = GoogleOAuth(credentialKey: AccountIndex.credentialKey(id))
        clients[id] = client
        return client
    }

    private func transferCredential(from source: String, to account: GoogleAccount) throws {
        guard let credential = try KeychainStore.read(source) else { throw OAuthError.notConnected }
        clients[account.id]?.invalidateCachedToken()
        try KeychainStore.write(credential, account: AccountIndex.credentialKey(account.id))
        var current = try index()
        current.add(account)
        try save(current)
        try KeychainStore.remove(source)
        pending.invalidateCachedToken()
        legacy.invalidateCachedToken()
    }

    private func identify(using oauth: GoogleOAuth) async throws -> GoogleAccount {
        let token = try await oauth.accessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList/primary")!)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OAuthError.invalidResponse }
        guard response.statusCode == 200 else { throw OAuthError.response(response.statusCode) }
        let account = try JSONDecoder().decode(GoogleAccount.self, from: data)
        guard !account.id.isEmpty else { throw OAuthError.invalidResponse }
        return account
    }

    private func index() throws -> AccountIndex {
        guard let data = try KeychainStore.read("accounts-index") else { return AccountIndex() }
        return try JSONDecoder().decode(AccountIndex.self, from: data)
    }

    private func save(_ index: AccountIndex) throws {
        try KeychainStore.write(JSONEncoder().encode(index), account: "accounts-index")
    }
}
