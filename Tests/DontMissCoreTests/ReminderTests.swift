import Foundation
import Testing
@testable import DontMissCore

struct ReminderTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func meeting(_ id: String = "one", offset: TimeInterval = 60, duration: TimeInterval = 1800) -> Meeting {
        Meeting(eventID: id, calendarID: "primary", calendarName: "Work", title: "Standup",
                start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + duration))
    }

    @Test func exactLeadBoundary() {
        let ledger = ReminderLedger()
        #expect(ledger.due(in: [meeting()], now: now.addingTimeInterval(-0.001), leadTime: 60).isEmpty)
        #expect(ledger.due(in: [meeting()], now: now, leadTime: 60).count == 1)
    }

    @Test func snoozeAndDismissPersist() throws {
        var ledger = ReminderLedger()
        ledger.snooze(meeting(), until: now.addingTimeInterval(60))
        let copy = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(ledger))
        #expect(copy.due(in: [meeting()], now: now, leadTime: 60).isEmpty)
        #expect(copy.due(in: [meeting()], now: now.addingTimeInterval(60), leadTime: 60).count == 1)
        ledger.dismiss(meeting())
        #expect(ledger.due(in: [meeting()], now: now.addingTimeInterval(120), leadTime: 60).isEmpty)
    }

    @Test func wakeCatchupIsBounded() {
        let ledger = ReminderLedger()
        #expect(ledger.due(in: [meeting(offset: -600)], now: now, leadTime: 60).count == 1)
        #expect(ledger.due(in: [meeting(offset: -601)], now: now, leadTime: 60).isEmpty)
        #expect(ledger.due(in: [meeting(offset: -100, duration: 100)], now: now, leadTime: 60).isEmpty)
    }

    @Test func movedAndRecurringMeetingsRearm() {
        var ledger = ReminderLedger()
        ledger.dismiss(meeting())
        #expect(ledger.due(in: [meeting(offset: 59)], now: now, leadTime: 60).count == 1)
        #expect(ledger.due(in: [meeting("next-instance")], now: now, leadTime: 60).count == 1)
    }

    @Test func overlapHasStableOrderAndNoLostReminder() {
        var ledger = ReminderLedger()
        let events = [meeting("b"), meeting("a")]
        let due = ledger.due(in: events, now: now, leadTime: 60)
        #expect(due.count == 2)
        ledger.dismiss(due[0])
        #expect(ledger.due(in: events, now: now, leadTime: 60) == [due[1]])
    }

    @Test func cancelledEventsDisappearAndExpiredEntriesPrune() {
        var ledger = ReminderLedger()
        ledger.dismiss(meeting())
        #expect(ledger.due(in: [], now: now, leadTime: 60).isEmpty)
        ledger.prune(now: now.addingTimeInterval(2000))
        #expect(ledger.entries.isEmpty)
    }

    @Test func snoozeCanExtendPastCatchupButNotEventEnd() {
        var ledger = ReminderLedger()
        let event = meeting(offset: -700)
        ledger.snooze(event, until: now.addingTimeInterval(30))
        #expect(ledger.due(in: [event], now: now.addingTimeInterval(30), leadTime: 60).count == 1)
        #expect(ledger.due(in: [event], now: event.end, leadTime: 60).isEmpty)
    }
}
