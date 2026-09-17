import Foundation

public struct AccountSchedule: Codable, Equatable, Sendable {
    public var calendars: [CalendarInfo]
    public var meetings: [Meeting]
    public var selectedIDs: Set<String>?
    public var lastSync: Date?

    public init(calendars: [CalendarInfo] = [], meetings: [Meeting] = [],
                selectedIDs: Set<String>? = nil, lastSync: Date? = nil) {
        self.calendars = calendars
        self.meetings = meetings
        self.selectedIDs = selectedIDs
        self.lastSync = lastSync
    }

    public mutating func initializeSelection(from calendars: [CalendarInfo]) {
        guard selectedIDs == nil else { return }
        selectedIDs = Set(calendars.filter { $0.primary == true }.map(\.id))
        if selectedIDs?.isEmpty == true, let first = calendars.first { selectedIDs = [first.id] }
    }

    public mutating func select(_ calendarID: String, enabled: Bool) {
        var selection = selectedIDs ?? []
        if enabled { selection.insert(calendarID) } else { selection.remove(calendarID) }
        selectedIDs = selection
        meetings.removeAll { !selection.contains($0.calendarID) }
    }
}

public struct MultiAccountSchedule: Codable, Equatable, Sendable {
    public var accounts: [String: AccountSchedule] = [:]
    public init() {}

    public func upcoming(now: Date) -> [Meeting] {
        var seen = Set<String>()
        return accounts.keys.sorted().flatMap { id -> [Meeting] in
            guard let account = accounts[id] else { return [] }
            return account.meetings.filter {
                $0.end > now && account.selectedIDs?.contains($0.calendarID) == true
                    && seen.insert($0.reminderID).inserted
            }
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    public mutating func retainAccounts(_ ids: Set<String>) {
        accounts = accounts.filter { ids.contains($0.key) }
    }
}
