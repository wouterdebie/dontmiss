import Foundation
import Testing
@testable import DontMissCore

struct AgendaTests {
    func event(_ id: String, start: Date, end: Date) -> Meeting {
        Meeting(eventID: id, calendarID: "work", calendarName: "Work", title: id, start: start, end: end)
    }

    @Test func todayFilterAndGroupingUseLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-16T23:00:00-05:00"))
        let laterToday = event("today", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(3000))
        let tomorrow = event("tomorrow", start: now.addingTimeInterval(5400), end: now.addingTimeInterval(7200))
        let ongoing = event("ongoing", start: now.addingTimeInterval(-86400), end: now.addingTimeInterval(300))
        let ended = event("ended", start: now.addingTimeInterval(-3600), end: now)
        let all = Agenda.days(meetings: [tomorrow, laterToday, ended, ongoing], now: now, todayOnly: false, calendar: calendar)
        #expect(all.count == 2)
        #expect(all.first?.meetings.map(\.eventID) == ["ongoing", "today"])
        let today = Agenda.days(meetings: [tomorrow, laterToday], now: now, todayOnly: true, calendar: calendar)
        #expect(today.flatMap(\.meetings).map(\.eventID) == ["today"])
    }

    @Test func todayFilterHandlesTwentyFiveHourDSTDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-11-01T00:00:00-05:00"))
        let late = try #require(formatter.date(from: "2026-11-01T23:30:00-06:00"))
        let next = try #require(formatter.date(from: "2026-11-02T00:30:00-06:00"))
        let events = [event("late", start: late, end: late.addingTimeInterval(600)),
                      event("next", start: next, end: next.addingTimeInterval(600))]
        #expect(Agenda.days(meetings: events, now: now, todayOnly: true, calendar: calendar)
            .flatMap(\.meetings).map(\.eventID) == ["late"])
    }

    @Test func emptyAgendaIsEmpty() {
        #expect(Agenda.days(meetings: [], now: Date(), todayOnly: false).isEmpty)
    }
}
