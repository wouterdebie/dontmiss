import Foundation

public enum CalendarAPIError: LocalizedError {
    case http(Int)
    case invalidResponse
    case invalidEvent
    case paginationLoop

    public var errorDescription: String? {
        switch self {
        case .http(401): "Google authorization expired or was revoked. Disconnect and connect again."
        case .http(403): "Google denied Calendar access. Check the API is enabled and both read-only permissions were granted."
        case .http(429): "Google Calendar rate limit reached. Don't Miss will retry at the next refresh."
        case .http(let status): "Google Calendar request failed (HTTP \(status))."
        case .invalidResponse: "Google Calendar returned an invalid response."
        case .invalidEvent: "A timed Google Calendar event has missing or invalid dates. The last successful schedule was kept."
        case .paginationLoop: "Google Calendar returned a repeated pagination token."
        }
    }
}

public struct GoogleCalendarClient: Sendable {
    private let session: URLSession
    private let accessToken: @Sendable () async throws -> String

    public init(session: URLSession = .shared,
                accessToken: @escaping @Sendable () async throws -> String) {
        self.session = session
        self.accessToken = accessToken
    }

    public func calendars() async throws -> [CalendarInfo] {
        try await pages(path: "users/me/calendarList", query: [
            URLQueryItem(name: "maxResults", value: "250")
        ])
    }

    public func meetings(calendars: [CalendarInfo], now: Date) async throws -> [Meeting] {
        var result: [Meeting] = []
        let formatter = ISO8601DateFormatter()
        for calendar in calendars {
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/?#%")
            guard let identifier = calendar.id.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw CalendarAPIError.invalidResponse
            }
            let events: [GoogleEvent] = try await pages(path: "calendars/\(identifier)/events", query: [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "maxResults", value: "2500"),
                URLQueryItem(name: "timeMin", value: formatter.string(from: now.addingTimeInterval(-600))),
                URLQueryItem(name: "timeMax", value: formatter.string(from: now.addingTimeInterval(7 * 86400)))
            ])
            result += try events.compactMap { try $0.meeting(calendar: calendar) }
        }
        // Shared events on different selected calendars remain distinct.
        return result.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    private struct Page<Item: Decodable>: Decodable {
        let items: [Item]?
        let nextPageToken: String?
    }

    private func pages<Item: Decodable>(path: String, query: [URLQueryItem]) async throws -> [Item] {
        var result: [Item] = []
        var next: String?
        var seen = Set<String>()
        repeat {
            guard var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/" + path) else {
                throw CalendarAPIError.invalidResponse
            }
            components.queryItems = query + (next.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            guard let url = components.url else { throw CalendarAPIError.invalidResponse }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw CalendarAPIError.invalidResponse }
            guard response.statusCode == 200 else { throw CalendarAPIError.http(response.statusCode) }
            let page = try JSONDecoder().decode(Page<Item>.self, from: data)
            result += page.items ?? []
            next = page.nextPageToken
            if let next, !seen.insert(next).inserted { throw CalendarAPIError.paginationLoop }
        } while next != nil
        return result
    }
}
