import Foundation
import CryptoKit
import Security

public enum OAuthError: LocalizedError {
    case configuration(String)
    case keychain(OSStatus)
    case random(OSStatus)
    case notConnected
    case cancelled
    case timedOut
    case browser
    case callback
    case denied
    case listener(String)
    case response(Int)
    case invalidResponse
    case reconnect
    case missingScopes
    case busy
    case revocation

    public var errorDescription: String? {
        switch self {
        case .configuration(let message): message
        case .keychain(let status): "Keychain operation failed (\(status)). Check Keychain access for Don't Miss."
        case .random(let status): "Could not generate secure OAuth randomness (\(status))."
        case .notConnected: "Connect Google Calendar first."
        case .cancelled: "Google sign-in was cancelled."
        case .timedOut: "Google sign-in timed out. Try connecting again."
        case .browser: "Could not open the system browser for Google sign-in."
        case .callback: "The Google OAuth callback was invalid."
        case .denied: "Google Calendar access was not granted."
        case .listener(let message): "Could not start the local OAuth callback listener: \(message)"
        case .response(let status): "Google OAuth request failed (HTTP \(status)). Try again."
        case .invalidResponse: "Google returned an incomplete OAuth response."
        case .reconnect: "Google authorization expired or was revoked. Disconnect and reconnect your calendar."
        case .missingScopes: "Both Calendar read-only permissions are required. Connect again and grant both permissions."
        case .busy: "A Google sign-in is already in progress."
        case .revocation: "Local credentials were cleared, but Google revocation failed. Remove Don't Miss from your Google account's third-party connections if needed."
        }
    }
}

struct ClientConfiguration: Codable {
    let clientID: String
    let clientSecret: String

    static func parse(_ data: Data) throws -> Self {
        struct Download: Decodable {
            struct Installed: Decodable {
                let client_id: String
                let client_secret: String
                let redirect_uris: [String]
            }
            let installed: Installed?
        }
        let download: Download
        do { download = try JSONDecoder().decode(Download.self, from: data) }
        catch { throw OAuthError.configuration("Invalid OAuth JSON. Download a Desktop app client from Google Cloud.") }
        guard let installed = download.installed,
              installed.client_id.hasSuffix(".apps.googleusercontent.com"),
              !installed.client_secret.isEmpty,
              installed.redirect_uris.contains(where: {
                  guard let url = URL(string: $0) else { return false }
                  return url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(url.host ?? "")
              }) else {
            throw OAuthError.configuration("Import a Google Desktop app OAuth client with a loopback redirect, not a Web client.")
        }
        return Self(clientID: installed.client_id, clientSecret: installed.client_secret)
    }
}

enum OAuthSupport {
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.events.readonly",
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    ]

    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw OAuthError.random(status) }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    static func equal(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8), right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func callback(target: String, state: String) throws -> String {
        guard let parts = URLComponents(string: "http://127.0.0.1" + target),
              parts.path == "/oauth/callback", parts.fragment == nil,
              let items = parts.queryItems else { throw OAuthError.callback }
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, let actualState = states[0].value, equal(state, actualState) else {
            throw OAuthError.callback
        }
        if items.contains(where: { $0.name == "error" }) { throw OAuthError.denied }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes[0].value, !code.isEmpty else { throw OAuthError.callback }
        return code
    }
}

enum KeychainStore {
    private static let service = "dev.wouter.dontmiss.google"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw OAuthError.keychain(status) }
        guard let data = result as? Data else { throw OAuthError.invalidResponse }
        return data
    }

    static func write(_ data: Data, account: String) throws {
        let query = query(account)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw OAuthError.keychain(added) }
        } else if status != errSecSuccess {
            throw OAuthError.keychain(status)
        }
    }

    static func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OAuthError.keychain(status) }
    }
}
