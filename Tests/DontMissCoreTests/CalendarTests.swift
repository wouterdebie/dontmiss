import Foundation
import Testing
@testable import DontMissCore

struct CalendarTests {
    let calendar = CalendarInfo(id: "work@example.com", summary: "Work", primary: true)

    func event(_ extra: String = "", start: String = """
        "start":{"dateTime":"2026-09-16T12:00:00-05:00"},
        "end":{"dateTime":"2026-09-16T13:00:00-05:00"}
        """) throws -> GoogleEvent {
        try JSONDecoder().decode(GoogleEvent.self, from: Data("""
        {"id":"event",\(start)\(extra)}
        """.utf8))
    }

    @Test func offsetsAndFractionalSeconds() throws {
        let meeting = try #require(try event().meeting(calendar: calendar))
        #expect(meeting.end.timeIntervalSince(meeting.start) == 3600)
        #expect(meeting.title == "(Untitled event)")
        let fractional = try event(start: """
            "start":{"dateTime":"2026-09-16T17:00:00.000Z"},
            "end":{"dateTime":"2026-09-16T18:00:00.000Z"}
            """).meeting(calendar: calendar)
        #expect(fractional?.start == meeting.start)
    }

    @Test func filters() throws {
        #expect(try event(#","status":"cancelled""#).meeting(calendar: calendar) == nil)
        #expect(try event(#","attendees":[{"self":true,"responseStatus":"declined"}]"#).meeting(calendar: calendar) == nil)
        #expect(try event(#","eventType":"workingLocation""#).meeting(calendar: calendar) == nil)
        #expect(try event(start: #""start":{"date":"2026-09-16"},"end":{"date":"2026-09-17"}"#).meeting(calendar: calendar) == nil)
        #expect(try event(#","attendees":[{"self":false,"responseStatus":"declined"}]"#).meeting(calendar: calendar) != nil)
    }

    @Test func malformedTimedEventFailsExplicitly() throws {
        let invalid = try event(start: #""start":{"dateTime":"nonsense"},"end":{"dateTime":"nonsense"}"#)
        #expect(throws: CalendarAPIError.self) { try invalid.meeting(calendar: calendar) }
    }

    @Test func conferenceLinksAndUntrustedSchemes() throws {
        let video = try event(#","conferenceData":{"entryPoints":[{"entryPointType":"video","uri":"https://meet.google.com/abc-defg-hij"}]}"#)
        #expect(try video.meeting(calendar: calendar)?.joinURL?.host == "meet.google.com")
        #expect(MeetingLink.webURL("file:///etc/passwd") == nil)
        #expect(MeetingLink.webURL("javascript:alert(1)") == nil)
        #expect(MeetingLink.find(in: "https://zoom.us.evil.example/j/123") == nil)
        #expect(MeetingLink.find(in: "https://company.zoom.us/j/123")?.host == "company.zoom.us")
        #expect(MeetingLink.find(in: "https://example.com, then https://meet.google.com/abc-defg-hij")?.host == "meet.google.com")
    }

    @Test func detailsDecodeWithoutExtraScopes() throws {
        let detailed = try event(#","htmlLink":"https://calendar.google.com/calendar/event?eid=test","location":"Room 2","description":"<p>Plan &amp; review</p><p>Next steps</p>","recurringEventId":"series","organizer":{"displayName":"Alex","email":"alex@example.invalid"},"attendees":[{"displayName":"Alex","email":"alex@example.invalid","responseStatus":"accepted"},{"self":true,"email":"me@example.invalid","responseStatus":"tentative"}]"#)
        let meeting = try #require(try detailed.meeting(calendar: calendar))
        #expect(meeting.calendarURL?.host == "calendar.google.com")
        #expect(meeting.location == "Room 2")
        #expect(meeting.notes == "Plan & review\nNext steps")
        #expect(meeting.isRecurring == true)
        #expect(meeting.organizer?.displayName == "Alex")
        #expect(meeting.guests?.first?.isOrganizer == true)
        #expect(meeting.guests?.last?.isSelf == true)
        #expect(meeting.guests?.last?.response == "tentative")
    }

    @Test func oldCachedMeetingsRemainReadable() throws {
        let original = try #require(try event().meeting(calendar: calendar))
        let oldFields: Set<String> = ["eventID", "calendarID", "calendarName", "title", "start", "end", "joinURL"]
        let data = try JSONEncoder().encode(original)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let oldData = try JSONSerialization.data(withJSONObject: json.filter { oldFields.contains($0.key) })
        let restored = try JSONDecoder().decode(Meeting.self, from: oldData)
        #expect(restored.id == original.id)
        #expect(restored.start == original.start)
        #expect(restored.guests == nil)
        #expect(restored.isRecurring == nil)
    }

    @Test func notesArePlainTextAndDoNotRenderRemoteContent() {
        #expect(EventNotes.plainText(#"<script>alert(1)</script><style>body{}</style><p>Hello<br>world<img src="https://example.invalid/tracker"></p>"#) == "Hello\nworld")
        #expect(EventNotes.plainText("Plain notes &amp; a link") == "Plain notes & a link")
        #expect(MeetingLink.serviceName(for: URL(string: "https://company.zoom.us/j/123")) == "Zoom")
        #expect(MeetingLink.serviceName(for: URL(string: "https://zoom.us.evil.invalid/j/123")) == "Video call")
    }
}
