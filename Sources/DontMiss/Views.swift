import SwiftUI
import DontMissCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    AppIconView(size: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Don't Miss").font(.largeTitle.bold())
                        Text("Meetings that won't slip past you.").foregroundStyle(.secondary)
                    }
                }
                GroupBox("Google accounts") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.connected ? "\(model.accounts.count) account(s) connected · read-only access" :
                                model.clientConfigured ? "OAuth client ready. Connect your calendar account." :
                                "Import a Google Desktop OAuth client to get started.")
                        ForEach(model.accounts) { account in
                            HStack {
                                Label(account.label, systemImage: "person.crop.circle")
                                    .textSelection(.enabled)
                                Spacer()
                                Button("Disconnect") { Task { await model.disconnect(account) } }
                                    .disabled(model.authenticating || model.disconnecting || model.restoring)
                            }
                        }
                        HStack {
                            Button("Import OAuth JSON...") { model.chooseConfiguration() }
                                .disabled(model.connected || model.authenticating || model.restoring || model.disconnecting)
                            if model.authenticating {
                                ProgressView().controlSize(.small)
                                Button("Cancel") { model.cancelConnection() }
                            } else {
                                Button(model.connected ? "Add Google account" : "Connect Google Calendar") {
                                    Task { await model.connect() }
                                }
                                .disabled(!model.clientConfigured || model.restoring || model.disconnecting)
                            }
                        }
                        if model.restoring || model.disconnecting {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(model.restoring ? "Restoring accounts..." : "Disconnecting...")
                            }
                        }
                        Text("Use the same OAuth client for all accounts. Each account has separate Keychain tokens and calendar selections. Don't Miss never modifies events.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("Calendars") {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.accounts.isEmpty {
                            Text("Your calendars appear after connecting.").foregroundStyle(.secondary)
                        }
                        ForEach(model.accounts) { account in
                            Text(account.label).font(.headline).padding(.top, 6)
                            let schedule = model.schedules.accounts[account.id]
                            if let calendars = schedule?.calendars, !calendars.isEmpty {
                                ForEach(calendars) { calendar in
                                    Toggle(calendar.summary + (calendar.primary == true ? " (primary)" : ""),
                                           isOn: Binding(
                                            get: { model.schedules.accounts[account.id]?.selectedIDs?.contains(calendar.id) == true },
                                            set: { model.setSelected(calendar, for: account.id, enabled: $0) }))
                                }
                            } else {
                                Text("Waiting for this account's calendars...").font(.caption).foregroundStyle(.secondary)
                            }
                            if let lastSync = schedule?.lastSync {
                                Text("Synced \(lastSync.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                        if model.connected {
                            HStack {
                                Button("Refresh now") { Task { await model.refresh() } }.disabled(model.refreshing)
                                if model.refreshing { ProgressView().controlSize(.small) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("Reminders") {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(value: $model.leadMinutes, in: 0...30) {
                            Text(model.leadMinutes == 0 ? "Alert at event start" : "Alert \(model.leadMinutes) minute(s) before")
                        }
                        Toggle("Play a sound when the alert appears", isOn: $model.soundEnabled)
                        Toggle("Start Don't Miss at login", isOn: Binding(
                            get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                        Button("Show test alert on this display") { model.testAlert() }
                        Text("Alerts appear only on the display containing your mouse pointer when they fire. They stay on that display until dismissed; other displays remain usable.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Timed events only, including events without a meeting link. All-day, declined, focus-time, out-of-office and working-location events are skipped. Snooze delays an alert by one minute.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                UpdateSettingsView(updates: model.updates)
                if let errors = model.errors {
                    Text(errors).foregroundStyle(.red).textSelection(.enabled)
                }
                Text("Keep Don't Miss running. Calendar changes sync every minute; cached reminders still work offline. After waking, events up to 10 minutes late can alert if they haven't ended. The app cannot alert while your Mac is asleep or replace the lock screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 650)
        .tint(ReminderPalette.accent(for: colorScheme))
    }
}
