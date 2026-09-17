import Foundation
import Testing
@testable import DontMissAuth

struct OAuthTests {
    @Test func accountsHaveSeparateCredentialKeysAndReconnectDoesNotDuplicate() throws {
        #expect(AccountIndex.credentialKey("personal@example.com") != AccountIndex.credentialKey("work@example.com"))
        #expect(AccountIndex.credentialKey("personal@example.com") == AccountIndex.credentialKey("personal@example.com"))
        var index = AccountIndex()
        index.add(GoogleAccount(id: "personal@example.com"))
        index.add(GoogleAccount(id: "work@example.com"))
        index.add(GoogleAccount(id: "personal@example.com"))
        #expect(index.accounts.count == 2)
        let restored = try JSONDecoder().decode(AccountIndex.self, from: JSONEncoder().encode(index))
        #expect(restored.accounts == index.accounts)
        index.accounts.removeAll { $0.id == "personal@example.com" }
        #expect(index.accounts.map(\.id) == ["work@example.com"])
    }

    @Test func pkceRFC7636Vector() {
        #expect(OAuthSupport.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomVerifier() throws {
        let first = try OAuthSupport.random()
        #expect(first.count == 43)
        #expect(first != (try OAuthSupport.random()))
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func formEncoding() {
        #expect(String(data: OAuthSupport.form(["code": "a+b&= /"]), encoding: .utf8) == "code=a%2Bb%26%3D%20%2F")
    }

    @Test func callbackValidation() throws {
        #expect(try OAuthSupport.callback(target: "/oauth/callback?state=valid&code=a%2Bb", state: "valid") == "a+b")
        #expect(throws: OAuthError.self) { try OAuthSupport.callback(target: "/wrong?state=valid&code=x", state: "valid") }
        #expect(throws: OAuthError.self) { try OAuthSupport.callback(target: "/oauth/callback?state=wrong&code=x", state: "valid") }
        #expect(throws: OAuthError.self) { try OAuthSupport.callback(target: "/oauth/callback?state=valid&state=valid&code=x", state: "valid") }
        #expect(throws: OAuthError.self) { try OAuthSupport.callback(target: "/oauth/callback?state=valid&error=access_denied", state: "valid") }
        #expect(throws: OAuthError.self) { try OAuthSupport.callback(target: "/oauth/callback?state=valid&code=", state: "valid") }
    }

    @Test func desktopConfiguration() throws {
        let valid = Data(#"{"installed":{"client_id":"example.apps.googleusercontent.com","client_secret":"not-a-real-secret","redirect_uris":["http://localhost"]}}"#.utf8)
        #expect(try ClientConfiguration.parse(valid).clientID == "example.apps.googleusercontent.com")
        let web = Data(#"{"web":{"client_id":"example.apps.googleusercontent.com"}}"#.utf8)
        #expect(throws: OAuthError.self) { try ClientConfiguration.parse(web) }
        #expect(throws: OAuthError.self) { try ClientConfiguration.parse(Data("not JSON".utf8)) }
    }

    @Test @MainActor func loopbackRoundTrip() async throws {
        let listener = LoopbackListener(state: "test-state")
        let redirect = try await listener.start()
        #expect(redirect.host == "127.0.0.1")
        #expect(redirect.port != nil && redirect.port != 0)
        var parts = try #require(URLComponents(url: redirect, resolvingAgainstBaseURL: false))
        parts.queryItems = [URLQueryItem(name: "state", value: "test-state"), URLQueryItem(name: "code", value: "test-code")]
        let (data, response) = try await URLSession.shared.data(from: try #require(parts.url))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(!data.isEmpty)
        #expect(try await listener.code() == "test-code")
    }

    @Test @MainActor func cancelledListenerFinishes() async throws {
        let listener = LoopbackListener(state: "test-state")
        _ = try await listener.start()
        listener.cancel()
        await #expect(throws: OAuthError.self) { try await listener.code() }
    }
}
