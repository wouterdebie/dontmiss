import SwiftUI
import DontMissCore

struct EventDetailsView: View {
    @ObservedObject var model: AppModel
    let original: Meeting
    @Environment(\.colorScheme) private var colorScheme
    @State private var guestsExpanded = true
    @State private var copied = false

    private var meeting: Meeting { model.meeting(id: original.id) ?? original }
    private var accent: Color { ReminderPalette.accent(for: colorScheme) }
    private var preference: EventReminderPreference? { model.eventPreferences.preference(for: meeting) }
    private var muted: Bool { preference?.isMuted == true }
    private var customMinutes: Int? { preference?.leadMinutes }
    private var canEdit: Bool { model.meeting(id: original.id) != nil && meeting.end > model.now }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heading
                    if !canEdit {
                        Label("This event has ended or is no longer in your current schedule.",
                              systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    timeAndLocation
                    if meeting.joinURL != nil { meetingLink }
                    reminderControls
                    if let notes = meeting.notes, !notes.isEmpty {
                        DetailCard(title: "Notes", symbol: "text.alignleft") {
                            Text(notes).font(.body).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    guests
                    if let error = model.operationError {
                        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("Read-only calendar access").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.closeEvent() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(minWidth: 540, minHeight: 460)
        .tint(accent)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EVENT DETAILS").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(accent)
            Text(meeting.title).font(.system(size: 30, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack(spacing: 14) {
                Label(meeting.calendarName, systemImage: "calendar")
                if meeting.isRecurring == true { Label("Recurring", systemImage: "repeat") }
            }
            .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { model.testAlert(meeting) } label: { Label("Preview reminder", systemImage: "eye") }
                Button { model.openInCalendar(meeting) } label: {
                    Label("Open in Google Calendar", systemImage: "arrow.up.right.square")
                }
                .disabled(meeting.calendarURL == nil)
            }
            .buttonStyle(.bordered).controlSize(.regular)
        }
    }

    private var timeAndLocation: some View {
        DetailCard(title: "When & where", symbol: "clock") {
            VStack(alignment: .leading, spacing: 10) {
                Text(meeting.start.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.headline)
                Text("\(meeting.start.formatted(date: .omitted, time: .shortened)) - \(meeting.end.formatted(date: .omitted, time: .shortened))  ·  \(EventFormatting.duration(meeting))  ·  \(TimeZone.current.abbreviation(for: meeting.start) ?? TimeZone.current.identifier)")
                    .foregroundStyle(.secondary)
                if !Calendar.current.isDate(meeting.start, inSameDayAs: meeting.end) {
                    Text("Ends \(meeting.end.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let location = meeting.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if EventLocation.searchQuery(for: location) != nil {
                        EventLocationMapView(location: location).id(location)
                    }
                }
                if let organizer = meeting.organizer {
                    Label("Organized by \(organizer.displayName)", systemImage: "person.crop.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var meetingLink: some View {
        DetailCard(title: MeetingLink.serviceName(for: meeting.joinURL), symbol: "video") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your meeting link").font(.callout.weight(.medium))
                    Text(meeting.joinURL?.absoluteString ?? "")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button {
                    copied = model.copyMeetingLink(meeting)
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .help(copied ? "Link copied" : "Copy meeting link")
                    .accessibilityLabel(copied ? "Link copied" : "Copy meeting link")
                Button { model.join(meeting) } label: {
                    Text("Join").foregroundStyle(colorScheme == .dark ? ReminderPalette.ink : .white)
                }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    private var reminderControls: some View {
        DetailCard(title: "Your reminder", symbol: muted ? "bell.slash" : "bell.badge") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Alert for this occurrence", isOn: Binding(
                    get: { !muted },
                    set: { model.setReminder(for: meeting, muted: !$0, leadMinutes: customMinutes) }))
                    .toggleStyle(.switch).disabled(!canEdit)
                Toggle("Use a custom lead time", isOn: Binding(
                    get: { customMinutes != nil },
                    set: { model.setReminder(for: meeting, muted: muted, leadMinutes: $0 ? model.leadMinutes : nil) }))
                    .disabled(muted || !canEdit)
                if customMinutes != nil {
                    Stepper(value: Binding(
                        get: { customMinutes ?? model.leadMinutes },
                        set: { model.setReminder(for: meeting, muted: muted, leadMinutes: $0) }), in: 0...30) {
                            Text((customMinutes ?? 0) == 0 ? "At the event start" : "\(customMinutes ?? 0) minutes before")
                        }
                        .disabled(muted || !canEdit)
                } else {
                    Text(model.leadMinutes == 0 ? "Default: at the event start" : "Default: \(model.leadMinutes) minute(s) before")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Label(statusText, systemImage: muted ? "bell.slash" : "clock")
                    .font(.callout).foregroundStyle(muted ? .secondary : accent)
                HStack {
                    if preference != nil {
                        Button("Use defaults") { model.setReminder(for: meeting, muted: false, leadMinutes: nil) }
                    }
                    if model.reminderStatus(for: meeting) != .waiting {
                        Button("Re-arm reminder") { model.rearmReminder(for: meeting) }
                            .disabled(muted)
                            .help("Allow this occurrence to alert again. It may appear immediately if its alert time has passed.")
                    }
                }
                .disabled(!canEdit)
                Text("Only this occurrence changes, even for recurring meetings. These settings stay in Don't Miss and never edit your calendar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        if muted { return "Muted for this occurrence" }
        if meeting.end <= model.now { return "This event has ended" }
        switch model.reminderStatus(for: meeting) {
        case .dismissed: return "Already acknowledged for this occurrence"
        case .snoozed(let until): return "Snoozed until \(until.formatted(date: .omitted, time: .shortened))"
        case .waiting:
            if meeting.start < model.now.addingTimeInterval(-600) { return "The catch-up window has passed" }
            let date = meeting.start.addingTimeInterval(-Double((customMinutes ?? model.leadMinutes) * 60))
            return date <= model.now ? "Ready to alert" : "Will alert \(date.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    private var guests: some View {
        DetailCard(title: "People", symbol: "person.2") {
            if let people = meeting.guests, !people.isEmpty {
                DisclosureGroup("\(people.count) guest(s)", isExpanded: $guestsExpanded) {
                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.offset) { index, person in
                            GuestRow(person: person, accent: accent).padding(.vertical, 10)
                            if index < people.count - 1 { Divider() }
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("No guest list was provided by this calendar.").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1) }
    }
}

private struct GuestRow: View {
    let person: MeetingGuest
    let accent: Color

    private var initials: String {
        person.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    private var response: (String, String, Color) {
        switch person.response {
        case "accepted": ("Accepted", "checkmark.circle.fill", accent)
        case "declined": ("Declined", "xmark.circle", .red)
        case "tentative": ("Tentative", "questionmark.circle", .secondary)
        default: ("Not responded", "circle.dotted", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(initials).font(.caption.weight(.semibold)).foregroundStyle(accent)
                .frame(width: 36, height: 36).background(accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(person.displayName).font(.callout.weight(.medium)).lineLimit(1)
                    if person.isOrganizer { Text("Organizer").font(.caption2).foregroundStyle(.secondary) }
                    if person.isSelf && person.displayName != "You" { Text("You").font(.caption2).foregroundStyle(.secondary) }
                }
                if let email = person.email, email != person.displayName {
                    Text(email).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1)
                }
            }
            Spacer()
            Label(response.0, systemImage: response.1).font(.caption).foregroundStyle(response.2)
        }
    }
}
