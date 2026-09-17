import Foundation
import Testing
@testable import DontMissCore

struct MultiAccountTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func meeting(calendarID: String = "shared", eventID: String = "event") -> Meeting {
        Meeting(eventID: eventID, calendarID: calendarID, calendarName: "Work", title: "Meeting",
                start: now.addingTimeInterval(60), end: now.addingTimeInterval(3600))
    }

    @Test func calendarSelectionIsScopedToAccount() {
        var store = MultiAccountSchedule()
        store.accounts["personal"] = AccountSchedule(meetings: [meeting()], selectedIDs: ["shared"])
        store.accounts["work"] = AccountSchedule(meetings: [meeting()], selectedIDs: ["shared"])
        store.accounts["personal"]?.select("shared", enabled: false)
        #expect(store.accounts["personal"]?.selectedIDs == [])
        #expect(store.accounts["work"]?.selectedIDs == ["shared"])
        #expect(store.upcoming(now: now).count == 1)
    }

    @Test func sharedCalendarDoesNotDoubleAlertAcrossAccounts() {
        var store = MultiAccountSchedule()
        store.accounts["personal"] = AccountSchedule(meetings: [meeting()], selectedIDs: ["shared"])
        store.accounts["work"] = AccountSchedule(meetings: [meeting()], selectedIDs: ["shared"])
        #expect(store.upcoming(now: now).count == 1)
        var ledger = ReminderLedger()
        ledger.dismiss(meeting())
        #expect(ledger.due(in: store.upcoming(now: now), now: now, leadTime: 60).isEmpty)
    }

    @Test func separateCalendarEventsRemainSeparate() {
        var store = MultiAccountSchedule()
        store.accounts["personal"] = AccountSchedule(meetings: [meeting(calendarID: "personal")], selectedIDs: ["personal"])
        store.accounts["work"] = AccountSchedule(meetings: [meeting(calendarID: "work")], selectedIDs: ["work"])
        #expect(store.upcoming(now: now).count == 2)
    }

    @Test func removingOneAccountKeepsOtherCacheAndSelection() {
        var store = MultiAccountSchedule()
        let work = AccountSchedule(meetings: [meeting()], selectedIDs: ["shared"], lastSync: now)
        store.accounts["personal"] = AccountSchedule()
        store.accounts["work"] = work
        store.retainAccounts(["work"])
        #expect(store.accounts["personal"] == nil)
        #expect(store.accounts["work"] == work)
        #expect(store.upcoming(now: now).count == 1)
    }

    @Test func emptySelectionSurvivesRefreshAndRestart() throws {
        var account = AccountSchedule(selectedIDs: [])
        account.initializeSelection(from: [CalendarInfo(id: "primary", summary: "Primary", primary: true)])
        #expect(account.selectedIDs == [])
        var store = MultiAccountSchedule()
        store.accounts["personal"] = account
        let restored = try JSONDecoder().decode(MultiAccountSchedule.self, from: JSONEncoder().encode(store))
        #expect(restored == store)
        #expect(restored.accounts["personal"]?.selectedIDs == [])
    }

    @Test func newAccountsGetIndependentDefaultSelections() {
        let calendars = [CalendarInfo(id: "primary", summary: "Primary", primary: true)]
        var first = AccountSchedule()
        first.initializeSelection(from: calendars)
        var second = AccountSchedule(selectedIDs: ["custom"])
        second.initializeSelection(from: calendars)
        #expect(first.selectedIDs == ["primary"])
        #expect(second.selectedIDs == ["custom"])
    }
}
