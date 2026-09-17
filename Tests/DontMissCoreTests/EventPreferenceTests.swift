import Foundation
import Testing
@testable import DontMissCore

struct EventPreferenceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func meeting(id: String = "occurrence", start: TimeInterval = 300, calendar: String = "work") -> Meeting {
        Meeting(eventID: id, calendarID: calendar, calendarName: "Work", title: "Meeting",
                start: now.addingTimeInterval(start), end: now.addingTimeInterval(start + 1800))
    }

    @Test func customLeadTimeUsesExactBoundary() throws {
        var preferences = EventReminderPreferences()
        preferences.set(try EventReminderPreference(leadMinutes: 5), for: meeting())
        let ledger = ReminderLedger()
        #expect(ledger.due(in: [meeting()], now: now, leadTime: 60).isEmpty)
        #expect(ledger.due(in: [meeting()], now: now.addingTimeInterval(-0.001), leadTime: 60, preferences: preferences).isEmpty)
        #expect(ledger.due(in: [meeting()], now: now, leadTime: 60, preferences: preferences).count == 1)
    }

    @Test func zeroMinuteOverrideWaitsUntilStart() throws {
        var preferences = EventReminderPreferences()
        let event = meeting(start: 60)
        preferences.set(try EventReminderPreference(leadMinutes: 0), for: event)
        let ledger = ReminderLedger()
        #expect(ledger.due(in: [event], now: now, leadTime: 60, preferences: preferences).isEmpty)
        #expect(ledger.due(in: [event], now: event.start, leadTime: 60, preferences: preferences).count == 1)
    }

    @Test func muteSuppressesSnoozeUntilUnmuted() throws {
        var preferences = EventReminderPreferences()
        let event = meeting(start: 60)
        var ledger = ReminderLedger()
        ledger.snooze(event, until: now)
        preferences.set(try EventReminderPreference(isMuted: true), for: event)
        #expect(ledger.due(in: [event], now: now, leadTime: 60, preferences: preferences).isEmpty)
        preferences.set(try EventReminderPreference(), for: event)
        #expect(ledger.due(in: [event], now: now, leadTime: 60, preferences: preferences).count == 1)
    }

    @Test func overridesFollowMovedOccurrenceButNotSeriesOrOtherCalendar() throws {
        var preferences = EventReminderPreferences()
        preferences.set(try EventReminderPreference(isMuted: true), for: meeting())
        #expect(preferences.preference(for: meeting(start: 600))?.isMuted == true)
        #expect(preferences.preference(for: meeting(id: "next-occurrence")) == nil)
        #expect(preferences.preference(for: meeting(calendar: "personal")) == nil)
    }

    @Test func preferencesSurviveRestartAndCleanupIsScoped() throws {
        var preferences = EventReminderPreferences()
        preferences.set(try EventReminderPreference(isMuted: true, leadMinutes: 10), for: meeting())
        preferences.set(try EventReminderPreference(leadMinutes: 2), for: meeting(calendar: "personal"))
        var restored = try JSONDecoder().decode(EventReminderPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(restored == preferences)
        restored.removeCalendars(["work"])
        #expect(restored.preference(for: meeting()) == nil)
        #expect(restored.preference(for: meeting(calendar: "personal"))?.leadMinutes == 2)
        restored.prune(now: now.addingTimeInterval(32 * 86400))
        #expect(restored.preference(for: meeting(calendar: "personal")) == nil)
    }

    @Test func invalidPreferencesFailExplicitly() {
        #expect(throws: EventReminderPreference.PreferenceError.self) { try EventReminderPreference(leadMinutes: -1) }
        #expect(throws: EventReminderPreference.PreferenceError.self) { try EventReminderPreference(leadMinutes: 31) }
        #expect(throws: EventReminderPreference.PreferenceError.self) {
            try JSONDecoder().decode(EventReminderPreference.self, from: Data(#"{"isMuted":false,"leadMinutes":100}"#.utf8))
        }
    }

    @Test func acknowledgedEventsNeedExplicitRearming() throws {
        let event = meeting(start: 60)
        var ledger = ReminderLedger()
        ledger.dismiss(event)
        var preferences = EventReminderPreferences()
        preferences.set(try EventReminderPreference(leadMinutes: 5), for: event)
        #expect(ledger.status(for: event) == .dismissed)
        #expect(ledger.due(in: [event], now: now, leadTime: 60, preferences: preferences).isEmpty)
        ledger.reset(event)
        #expect(ledger.status(for: event) == .waiting)
        #expect(ledger.due(in: [event], now: now, leadTime: 60, preferences: preferences).count == 1)
    }
}
