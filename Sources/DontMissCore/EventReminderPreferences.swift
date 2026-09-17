import Foundation

public struct EventReminderPreference: Codable, Equatable, Sendable {
    public let isMuted: Bool
    public let leadMinutes: Int?

    public init(isMuted: Bool = false, leadMinutes: Int? = nil) throws {
        if let leadMinutes, !(0...30).contains(leadMinutes) { throw PreferenceError.invalidLead }
        self.isMuted = isMuted
        self.leadMinutes = leadMinutes
    }

    enum CodingKeys: String, CodingKey { case isMuted, leadMinutes }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(isMuted: values.decode(Bool.self, forKey: .isMuted),
                      leadMinutes: values.decodeIfPresent(Int.self, forKey: .leadMinutes))
    }

    public enum PreferenceError: LocalizedError {
        case invalidLead
        public var errorDescription: String? { "Reminder lead time must be between 0 and 30 minutes." }
    }
}

public struct EventReminderPreferences: Codable, Equatable, Sendable {
    private struct Entry: Codable, Equatable, Sendable {
        let preference: EventReminderPreference
        let expires: Date
        let calendarID: String
    }
    private var entries: [String: Entry] = [:]
    public init() {}

    public func preference(for meeting: Meeting) -> EventReminderPreference? {
        entries[meeting.id]?.preference
    }

    public mutating func set(_ preference: EventReminderPreference, for meeting: Meeting) {
        if !preference.isMuted && preference.leadMinutes == nil {
            entries.removeValue(forKey: meeting.id)
        } else {
            entries[meeting.id] = Entry(preference: preference,
                                       expires: meeting.end.addingTimeInterval(30 * 86400),
                                       calendarID: meeting.calendarID)
        }
    }

    public mutating func prune(now: Date) { entries = entries.filter { $0.value.expires > now } }

    public mutating func removeCalendars(_ ids: Set<String>) {
        entries = entries.filter { !ids.contains($0.value.calendarID) }
    }
}
