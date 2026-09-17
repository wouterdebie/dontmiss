import Foundation

public struct CalendarInfo: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let summary: String
    public let primary: Bool?
}

public struct Meeting: Codable, Identifiable, Equatable, Sendable {
    public let eventID: String
    public let calendarID: String
    public let calendarName: String
    public let title: String
    public let start: Date
    public let end: Date
    public let joinURL: URL?
    public let calendarURL: URL?
    public let location: String?
    public let notes: String?
    public let organizer: MeetingGuest?
    public let guests: [MeetingGuest]?
    public let isRecurring: Bool?

    public var id: String {
        Data(calendarID.utf8).base64EncodedString() + ":" + Data(eventID.utf8).base64EncodedString()
    }

    // Moving an event should re-arm its reminder; changing its title should not.
    public var reminderID: String { "\(id):\(start.timeIntervalSince1970)" }

    public init(eventID: String, calendarID: String, calendarName: String, title: String,
                start: Date, end: Date, joinURL: URL? = nil, calendarURL: URL? = nil,
                location: String? = nil, notes: String? = nil, organizer: MeetingGuest? = nil,
                guests: [MeetingGuest]? = nil, isRecurring: Bool? = nil) {
        self.eventID = eventID
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.title = title
        self.start = start
        self.end = end
        self.joinURL = joinURL
        self.calendarURL = calendarURL
        self.location = location
        self.notes = notes
        self.organizer = organizer
        self.guests = guests
        self.isRecurring = isRecurring
    }
}

public struct MeetingGuest: Codable, Equatable, Sendable {
    public let name: String?
    public let email: String?
    public let response: String?
    public let isOrganizer: Bool
    public let isSelf: Bool

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if isSelf { return "You" }
        return email ?? "Guest"
    }

    public init(name: String? = nil, email: String? = nil, response: String? = nil,
                isOrganizer: Bool = false, isSelf: Bool = false) {
        self.name = name
        self.email = email
        self.response = response
        self.isOrganizer = isOrganizer
        self.isSelf = isSelf
    }
}

public struct GoogleEvent: Decodable, Sendable {
    struct Time: Decodable, Sendable {
        let dateTime: String?
        let date: String?
    }
    struct Attendee: Decodable, Sendable {
        let isSelf: Bool?
        let responseStatus: String?
        let displayName: String?
        let email: String?
        let organizer: Bool?
        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case responseStatus
            case displayName, email, organizer
        }
    }
    struct Conference: Decodable, Sendable {
        struct EntryPoint: Decodable, Sendable {
            let entryPointType: String?
            let uri: String?
        }
        let entryPoints: [EntryPoint]?
    }
    let id: String
    let summary: String?
    let status: String?
    let eventType: String?
    let start: Time?
    let end: Time?
    let attendees: [Attendee]?
    let hangoutLink: String?
    let conferenceData: Conference?
    let location: String?
    let description: String?
    let htmlLink: String?
    let organizer: Attendee?
    let recurringEventId: String?

    public func meeting(calendar: CalendarInfo) throws -> Meeting? {
        guard status != "cancelled",
              !["workingLocation", "focusTime", "outOfOffice", "birthday"].contains(eventType ?? ""),
              !(attendees ?? []).contains(where: { $0.isSelf == true && $0.responseStatus == "declined" })
        else { return nil }
        if start?.date != nil { return nil }
        guard let startText = start?.dateTime, let endText = end?.dateTime,
              let startDate = Self.parseDate(startText), let endDate = Self.parseDate(endText),
              endDate > startDate else {
            throw CalendarAPIError.invalidEvent
        }
        let conferenceURL = conferenceData?.entryPoints?
            .filter { $0.entryPointType == "video" }
            .compactMap { MeetingLink.webURL($0.uri) }.first
        let title = summary.flatMap { $0.isEmpty ? nil : $0 } ?? "(Untitled event)"
        return Meeting(eventID: id, calendarID: calendar.id, calendarName: calendar.summary,
                       title: title,
                       start: startDate, end: endDate,
                       joinURL: conferenceURL ?? MeetingLink.webURL(hangoutLink)
                        ?? MeetingLink.find(in: [location, description].compactMap { $0 }.joined(separator: "\n")),
                       calendarURL: MeetingLink.webURL(htmlLink), location: location,
                       notes: description.map(EventNotes.plainText),
                       organizer: organizer.map {
                           MeetingGuest(name: $0.displayName, email: $0.email, isOrganizer: true, isSelf: $0.isSelf == true)
                       },
                       guests: attendees?.map {
                           MeetingGuest(name: $0.displayName, email: $0.email, response: $0.responseStatus,
                                        isOrganizer: $0.organizer == true || ($0.email != nil && $0.email == organizer?.email),
                                        isSelf: $0.isSelf == true)
                       }, isRecurring: recurringEventId != nil)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

public enum MeetingLink {
    public static func serviceName(for url: URL?) -> String {
        guard let host = url?.host?.lowercased() else { return "Meeting" }
        let services = [("meet.google.com", "Google Meet"), ("zoom.us", "Zoom"),
                        ("teams.microsoft.com", "Teams"), ("teams.live.com", "Teams"),
                        ("webex.com", "Webex"), ("whereby.com", "Whereby"), ("meet.jit.si", "Jitsi")]
        return services.first { host == $0.0 || host.hasSuffix("." + $0.0) }?.1 ?? "Video call"
    }

    public static func webURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    public static func find(in text: String) -> URL? {
        let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
                     "webex.com", "whereby.com", "meet.jit.si"]
        // A fixed Foundation detector pattern cannot be supplied by calendar content.
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = webURL(match.url?.absoluteString), let host = url.host?.lowercased() else { continue }
            if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
        }
        return nil
    }
}
