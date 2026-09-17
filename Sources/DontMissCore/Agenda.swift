import Foundation

public struct AgendaDay: Identifiable, Equatable, Sendable {
    public let id: Date
    public let meetings: [Meeting]
}

public enum Agenda {
    public static func days(meetings: [Meeting], now: Date, todayOnly: Bool,
                            calendar: Calendar = .current) -> [AgendaDay] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let filtered = meetings.filter { $0.end > now && (!todayOnly || $0.start < tomorrow) }
        let groups = Dictionary(grouping: filtered) { meeting in
            calendar.startOfDay(for: max(today, meeting.start))
        }
        return groups.keys.sorted().map { day in
            AgendaDay(id: day, meetings: (groups[day] ?? []).sorted {
                $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
            })
        }
    }
}
