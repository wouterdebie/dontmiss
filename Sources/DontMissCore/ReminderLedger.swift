import Foundation

public struct ReminderLedger: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        let expires: Date
        let snoozedUntil: Date?
    }
    public private(set) var entries: [String: Entry] = [:]
    public init() {}

    public func due(in meetings: [Meeting], now: Date, leadTime: TimeInterval,
                    preferences: EventReminderPreferences = EventReminderPreferences()) -> [Meeting] {
        meetings.filter { meeting in
            let preference = preferences.preference(for: meeting)
            guard meeting.end > now, preference?.isMuted != true else { return false }
            if let entry = entries[meeting.reminderID] {
                guard let snoozedUntil = entry.snoozedUntil else { return false }
                return now >= snoozedUntil
            }
            let effectiveLead = preference?.leadMinutes.map { Double($0 * 60) } ?? leadTime
            return meeting.start.addingTimeInterval(-effectiveLead) <= now
                && meeting.start >= now.addingTimeInterval(-600)
        }.sorted {
            $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }
    }

    public mutating func dismiss(_ meeting: Meeting) {
        entries[meeting.reminderID] = Entry(expires: meeting.end, snoozedUntil: nil)
    }

    public mutating func snooze(_ meeting: Meeting, until: Date) {
        entries[meeting.reminderID] = Entry(expires: meeting.end, snoozedUntil: until)
    }

    public enum Status: Equatable, Sendable {
        case waiting, dismissed, snoozed(until: Date)
    }

    public func status(for meeting: Meeting) -> Status {
        guard let entry = entries[meeting.reminderID] else { return .waiting }
        if let until = entry.snoozedUntil { return .snoozed(until: until) }
        return .dismissed
    }

    public mutating func reset(_ meeting: Meeting) { entries.removeValue(forKey: meeting.reminderID) }

    public mutating func prune(now: Date) {
        entries = entries.filter { $0.value.expires > now }
    }
}
