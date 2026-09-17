import SwiftUI
import DontMissCore

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var todayOnly = false
    private let contentInset: CGFloat = 18

    private var accent: Color { ReminderPalette.accent(for: colorScheme) }
    private var days: [AgendaDay] {
        Agenda.days(meetings: model.upcoming, now: model.now, todayOnly: todayOnly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Don't Miss").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("A little ahead of your day.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                toolbar
            }
            .padding(.horizontal, contentInset)
            Picker("Agenda range", selection: $todayOnly) {
                Text("Today").tag(true)
                Text("Next 7 days").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, contentInset)

            if !model.connected || model.selectedIDs.isEmpty || days.isEmpty {
                emptyState.padding(.horizontal, contentInset)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(days) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(dayLabel(day.id)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(day.meetings.count)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                ForEach(day.meetings) { meeting in
                                    AgendaEventRow(model: model, meeting: meeting)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, contentInset)
                    .background(AgendaScrollStyle())
                }
                .frame(height: min(460, CGFloat(days.reduce(0) { $0 + $1.meetings.count }) * 94 + CGFloat(days.count) * 34))
            }

            if let errors = model.errors {
                Button { model.showSettings() } label: {
                    Label(errors, systemImage: "exclamationmark.triangle")
                        .font(.caption).lineLimit(2).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).help("Open Settings for error details")
                .padding(.horizontal, contentInset)
            } else if model.stale {
                Label("Schedule may be out of date", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, contentInset)
            }
            Divider().padding(.horizontal, contentInset)
            HStack {
                if model.refreshing {
                    ProgressView().controlSize(.mini)
                    Text("Syncing calendars...").font(.caption).foregroundStyle(.secondary)
                } else if let lastSync = model.lastSync {
                    Text("Synced \(lastSync.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Read-only. Always your calendar.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                CheckForUpdatesButton(updates: model.updates)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, contentInset)
        }
        .padding(.vertical, 18).frame(width: 440)
        .tint(accent)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(!model.connected || model.refreshing).help("Refresh calendars")
            Button { model.testAlert() } label: { Image(systemName: "eye") }
                .help("Preview a reminder")
            Button { model.showSettings() } label: { Image(systemName: "slider.horizontal.3") }
                .help("Settings")
        }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.connected ? "calendar.badge.checkmark" : "calendar.badge.plus")
                .font(.system(size: 32)).foregroundStyle(accent)
            Text(!model.connected ? "Bring your calendars together" :
                    model.selectedIDs.isEmpty ? "Choose what matters" :
                    todayOnly ? "You're clear for today" : "A quiet week ahead")
                .font(.headline)
            Text(!model.connected ? "Connect an account to see your upcoming events." :
                    model.selectedIDs.isEmpty ? "Select calendars in Settings to start reminders." :
                    "No upcoming timed events in this view.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !model.connected || model.selectedIDs.isEmpty {
                Button("Open Settings") { model.showSettings() }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: model.now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: model.now),
           calendar.isDate(day, inSameDayAs: tomorrow) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private struct AgendaEventRow: View {
    @ObservedObject var model: AppModel
    let meeting: Meeting
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    private var accent: Color { ReminderPalette.accent(for: colorScheme) }
    private var preference: EventReminderPreference? { model.eventPreferences.preference(for: meeting) }
    private var live: Bool { meeting.start <= model.now && meeting.end > model.now }

    var body: some View {
        HStack(spacing: 8) {
            Button { model.showEvent(meeting) } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(meeting.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(live ? accent : .primary)
                        Text(meeting.end.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .monospacedDigit().frame(width: 73, alignment: .trailing).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(meeting.title)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(meeting.calendarName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 8) {
                            if live { Text("NOW").font(.system(size: 9, weight: .bold)).foregroundStyle(accent) }
                            if meeting.isRecurring == true {
                                Image(systemName: "repeat").accessibilityLabel("Recurring event")
                            }
                            if preference?.isMuted == true {
                                Label("Muted", systemImage: "bell.slash")
                            } else if let minutes = preference?.leadMinutes {
                                Label(minutes == 0 ? "At start" : "\(minutes)m early", systemImage: "bell")
                            } else if !live {
                                Text(EventFormatting.duration(meeting))
                            }
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Open event details")
            if meeting.joinURL != nil {
                Button { model.join(meeting) } label: {
                    Image(systemName: "video.fill").font(.system(size: 13)).foregroundStyle(accent)
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.borderless).help("Join with \(MeetingLink.serviceName(for: meeting.joinURL))")
                .accessibilityLabel("Join \(meeting.title)")
            } else {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary).frame(width: 30)
            }
        }
        .padding(10)
        .background(accent.opacity(hovered ? 0.13 : live ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(hovered ? 0.3 : 0.07), lineWidth: 1)
        }
        .onHover { hovered = $0 }
    }
}

enum EventFormatting {
    static func duration(_ meeting: Meeting) -> String {
        let minutes = max(1, Int(meeting.end.timeIntervalSince(meeting.start) / 60))
        if minutes < 60 { return "\(minutes) min" }
        let remainder = minutes % 60
        return remainder == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(remainder) min"
    }
}
