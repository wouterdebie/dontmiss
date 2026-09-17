import Foundation
import Testing
@testable import DontMissCore

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    // URLProtocol callbacks run on Foundation threads; every shared access is locked.
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [(Int, Data)] = []
        private var requests: [URLRequest] = []
        func reset(_ replies: [(Int, String)]) {
            lock.lock()
            defer { lock.unlock() }
            self.replies = replies.map { ($0.0, Data($0.1.utf8)) }
            requests = []
        }
        func take(for request: URLRequest) -> (Int, Data) {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            return replies.isEmpty ? (500, Data()) : replies.removeFirst()
        }
        func captured() -> [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.state.take(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct CalendarAPITests {
    func client() -> (GoogleCalendarClient, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        return (GoogleCalendarClient(session: session, accessToken: { "test-token" }), session)
    }

    @Test func calendarPaginationAndAuthorization() async throws {
        StubProtocol.state.reset([
            (200, #"{"items":[{"id":"one","summary":"One"}],"nextPageToken":"a+b/="}"#),
            (200, #"{"items":[{"id":"two","summary":"Two","primary":true}]}"#)
        ])
        let (api, session) = client()
        defer { session.invalidateAndCancel() }
        let calendars = try await api.calendars()
        #expect(calendars.map(\.id) == ["one", "two"])
        let requests = StubProtocol.state.captured()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" })
        let query = URLComponents(url: try #require(requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "pageToken" }?.value == "a+b/=")
    }

    @Test func eventPaginationRecurringExpansionAndWindow() async throws {
        StubProtocol.state.reset([
            (200, #"{"items":[{"id":"one","start":{"dateTime":"2026-09-16T17:00:00Z"},"end":{"dateTime":"2026-09-16T18:00:00Z"}}],"nextPageToken":"next"}"#),
            (200, #"{"items":[{"id":"two","start":{"dateTime":"2026-09-17T17:00:00Z"},"end":{"dateTime":"2026-09-17T18:00:00Z"}}]}"#)
        ])
        let (api, session) = client()
        defer { session.invalidateAndCancel() }
        let calendar = CalendarInfo(id: "a/b?#%@example.com", summary: "Work", primary: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let meetings = try await api.meetings(calendars: [calendar], now: now)
        #expect(meetings.map(\.eventID) == ["one", "two"])
        let url = try #require(StubProtocol.state.captured().first?.url)
        #expect(url.absoluteString.contains("a%2Fb%3F%23%25@example.com"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "singleEvents" }?.value == "true")
        #expect(query.first { $0.name == "showDeleted" }?.value == "false")
        let formatter = ISO8601DateFormatter()
        #expect(query.first { $0.name == "timeMin" }?.value == formatter.string(from: now.addingTimeInterval(-600)))
        #expect(query.first { $0.name == "timeMax" }?.value == formatter.string(from: now.addingTimeInterval(7 * 86400)))
    }

    @Test func errorsAreNotEmptySchedules() async throws {
        StubProtocol.state.reset([(403, "{}")])
        let (api, session) = client()
        defer { session.invalidateAndCancel() }
        await #expect(throws: CalendarAPIError.self) { try await api.calendars() }
    }

    @Test func repeatedPageTokenFails() async throws {
        StubProtocol.state.reset([
            (200, #"{"items":[],"nextPageToken":"same"}"#),
            (200, #"{"items":[],"nextPageToken":"same"}"#)
        ])
        let (api, session) = client()
        defer { session.invalidateAndCancel() }
        await #expect(throws: CalendarAPIError.self) { try await api.calendars() }
        #expect(StubProtocol.state.captured().count == 2)
    }
}
