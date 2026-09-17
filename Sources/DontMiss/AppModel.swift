import AppKit
import Combine
import DontMissAuth
import DontMissCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published private(set) var accounts: [GoogleAccount] = []
    @Published private(set) var schedules = MultiAccountSchedule()
    @Published private(set) var eventPreferences = EventReminderPreferences()
    @Published private(set) var restoring = true
    @Published private(set) var clientConfigured = false
    @Published private(set) var authenticating = false
    @Published private(set) var disconnecting = false
    @Published private(set) var refreshing = false
    @Published private(set) var now = Date()
    @Published var operationError: String?
    @Published private var syncErrors: [String: String] = [:]
    @Published private(set) var storageError: String?
    @Published var leadMinutes: Int {
        didSet {
            UserDefaults.standard.set(leadMinutes, forKey: "leadMinutes")
            tick()
        }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled

    let oauth = GoogleAccounts()
    let updates = AppUpdates()
    private var ledger = ReminderLedger()
    private let overlay = OverlayController()
    private var clock: Timer?
    private var syncTimer: Timer?
    private var sessionActive = true
    private var generation = 0
    private var refreshPending = false
    private var isDemo = false
    private var currentReminder: String?
    private var settingsWindow: NSWindow?
    private var eventWindow: NSWindow?
    private var agendaPreviewWindow: NSWindow?
    private var isPreviewSession = false
    private var legacySnapshot: Snapshot?

    var connected: Bool { !accounts.isEmpty }
    var selectedIDs: Set<String> { Set(schedules.accounts.values.flatMap { $0.selectedIDs ?? [] }) }
    var lastSync: Date? { schedules.accounts.values.compactMap(\.lastSync).min() }
    var errors: String? {
        let messages = [operationError, storageError].compactMap { $0 }
            + syncErrors.keys.sorted().compactMap { syncErrors[$0] }
        return messages.isEmpty ? nil : messages.joined(separator: "\n\n")
    }
    var upcoming: [Meeting] { schedules.upcoming(now: now) }
    var next: Meeting? { upcoming.first { $0.start >= now } }
    var stale: Bool {
        accounts.contains { account in
            schedules.accounts[account.id]?.lastSync.map { now.timeIntervalSince($0) > 300 } ?? true
        }
    }

    override init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["leadMinutes": 1, "soundEnabled": true])
        leadMinutes = max(0, min(30, defaults.integer(forKey: "leadMinutes")))
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        super.init()
    }

    func start(onReady: (@MainActor () -> Void)? = nil) {
        updates.start()
        do {
            clientConfigured = try oauth.hasClientConfiguration()
            accounts = try oauth.accounts()
            if try oauth.hasCredentials() { try loadSnapshot() }
        } catch { operationError = error.localizedDescription }
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for notification in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                             NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(wake), name: notification, object: nil)
        }
        for notification in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                             NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(self, selector: #selector(sleep), name: notification, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Task {
            do {
                accounts = try await oauth.restoreAccounts()
                migrateLegacySchedule()
                schedules.retainAccounts(Set(accounts.map(\.id)))
                persist()
            } catch { operationError = "Could not restore Google accounts: \(error.localizedDescription)" }
            restoring = false
            onReady?()
            await refresh()
        }
    }

    func stop() {
        clock?.invalidate()
        syncTimer?.invalidate()
        oauth.cancelSignIn()
        overlay.hide()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func importConfiguration(from url: URL) {
        guard !authenticating, !disconnecting, !restoring, !connected else {
            operationError = "Disconnect all accounts before replacing the OAuth client."
            return
        }
        do {
            try oauth.importClientConfiguration(from: url)
            clientConfigured = true
            operationError = nil
        } catch { operationError = error.localizedDescription }
    }

    func chooseConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Import the Desktop OAuth client JSON downloaded from Google Cloud."
        if panel.runModal() == .OK, let url = panel.url { importConfiguration(from: url) }
    }

    func connect() async {
        guard !authenticating, !disconnecting, !restoring else { return }
        authenticating = true
        defer { authenticating = false }
        do {
            _ = try await oauth.signIn()
            accounts = try oauth.accounts()
            migrateLegacySchedule()
            generation += 1
            operationError = nil
            await refresh()
        } catch { operationError = error.localizedDescription }
    }

    func cancelConnection() { oauth.cancelSignIn() }

    func disconnect(_ account: GoogleAccount) async {
        guard !disconnecting, !authenticating, !restoring else { return }
        disconnecting = true
        defer { disconnecting = false }
        let previousCalendars = Set(schedules.accounts[account.id]?.calendars.map(\.id) ?? [])
        generation += 1
        do {
            try await oauth.disconnect(account.id)
            operationError = nil
        } catch { operationError = error.localizedDescription }
        do {
            accounts = try oauth.accounts()
            schedules.retainAccounts(Set(accounts.map(\.id)))
            let remainingCalendars = Set(schedules.accounts.values.flatMap { $0.calendars.map(\.id) })
            eventPreferences.removeCalendars(previousCalendars.subtracting(remainingCalendars))
            syncErrors.removeValue(forKey: account.id)
            if !connected {
                overlay.hide()
                currentReminder = nil
                isDemo = false
                ledger = ReminderLedger()
                eventPreferences = EventReminderPreferences()
            }
            persist()
            tick()
        } catch { operationError = error.localizedDescription }
    }

    func setSelected(_ calendar: CalendarInfo, for accountID: String, enabled: Bool) {
        schedules.accounts[accountID, default: AccountSchedule()].select(calendar.id, enabled: enabled)
        generation += 1
        persist()
        tick()
        Task { await refresh() }
    }

    func refresh() async {
        guard connected, !restoring else { return }
        guard !refreshing else { refreshPending = true; return }
        refreshing = true
        let requestGeneration = generation
        defer {
            refreshing = false
            if refreshPending {
                refreshPending = false
                Task { await refresh() }
            }
        }
        for account in accounts {
            guard generation == requestGeneration else { return }
            let api = GoogleCalendarClient { [oauth] in try await oauth.accessToken(for: account.id) }
            do {
                let available = try await api.calendars()
                guard generation == requestGeneration else { return }
                var schedule = schedules.accounts[account.id] ?? AccountSchedule()
                schedule.initializeSelection(from: available)
                let events = try await api.meetings(
                    calendars: available.filter { schedule.selectedIDs?.contains($0.id) == true }, now: Date())
                guard generation == requestGeneration else { return }
                schedule.calendars = available
                schedule.meetings = events
                schedule.lastSync = Date()
                schedules.accounts[account.id] = schedule
                syncErrors.removeValue(forKey: account.id)
                ledger.prune(now: Date())
                eventPreferences.prune(now: Date())
                persist()
                tick()
            } catch {
                guard generation == requestGeneration else { return }
                syncErrors[account.id] = "\(account.label): \(error.localizedDescription)\nCached reminders remain active; retrying every minute."
            }
        }
    }

    func tick() {
        now = Date()
        guard sessionActive, !isDemo else { return }
        guard connected else { return }
        let due = ledger.due(in: upcoming, now: now, leadTime: Double(leadMinutes * 60),
                             preferences: eventPreferences)
        if let currentReminder, let active = due.first(where: { $0.reminderID == currentReminder }) {
            overlay.update(active, queued: due.count - 1)
            return
        }
        if currentReminder != nil { overlay.hide(); currentReminder = nil }
        guard let meeting = due.first else { return }
        currentReminder = meeting.reminderID
        overlay.show(meeting, queued: due.count - 1, action: { [weak self] action in
            guard let self, let latest = self.upcoming.first(where: { $0.reminderID == meeting.reminderID }) else { return }
            self.handle(action, meeting: latest)
        })
        if soundEnabled { NSSound.beep() }
    }

    private func handle(_ action: OverlayAction, meeting: Meeting) {
        switch action {
        case .join:
            guard let url = meeting.joinURL, NSWorkspace.shared.open(url) else {
                operationError = "Could not open the meeting link. Dismiss the alert and open it from your calendar."
                overlay.showError("Could not open the meeting link. You can still dismiss this alert.")
                return
            }
            if !isDemo { ledger.dismiss(meeting) }
        case .dismiss:
            if !isDemo { ledger.dismiss(meeting) }
        case .snooze:
            if !isDemo { ledger.snooze(meeting, until: Date().addingTimeInterval(60)) }
        }
        overlay.hide()
        currentReminder = nil
        isDemo = false
        persist()
        tick()
    }

    func testAlert(_ event: Meeting? = nil) {
        guard currentReminder == nil, !isDemo else {
            operationError = "Dismiss the active reminder before opening a preview."
            return
        }
        isDemo = true
        let meeting = Meeting(eventID: "demo", calendarID: "demo",
                              calendarName: event.map { "Preview - \($0.calendarName)" } ?? "Preview - no calendar event",
                              title: event?.title ?? "Your next meeting",
                              start: event?.start ?? Date().addingTimeInterval(60),
                              end: event?.end ?? Date().addingTimeInterval(1860), joinURL: event?.joinURL)
        overlay.show(meeting, queued: 0, action: { [weak self] action in self?.handle(action, meeting: meeting) })
        if soundEnabled { NSSound.beep() }
    }

    func smokeTestPassed() -> Bool { overlay.coversSelectedScreen }

    func join(_ meeting: Meeting) {
        guard let url = meeting.joinURL, NSWorkspace.shared.open(url) else {
            operationError = "Could not open the meeting link."
            return
        }
        ledger.dismiss(meeting)
        persist()
        tick()
    }

    func meeting(id: String) -> Meeting? {
        for accountID in schedules.accounts.keys.sorted() {
            if let event = schedules.accounts[accountID]?.meetings.first(where: { $0.id == id }) { return event }
        }
        return nil
    }

    func reminderStatus(for meeting: Meeting) -> ReminderLedger.Status { ledger.status(for: meeting) }

    func setReminder(for meeting: Meeting, muted: Bool, leadMinutes: Int?) {
        guard self.meeting(id: meeting.id) != nil, meeting.end > Date() else {
            operationError = "This event is no longer upcoming. Refresh your calendar before changing its reminder."
            return
        }
        do {
            let preference = try EventReminderPreference(isMuted: muted, leadMinutes: leadMinutes)
            eventPreferences.set(preference, for: meeting)
            operationError = nil
            persist()
            tick()
        } catch { operationError = error.localizedDescription }
    }

    func rearmReminder(for meeting: Meeting) {
        ledger.reset(meeting)
        persist()
        tick()
    }

    func openInCalendar(_ meeting: Meeting) {
        guard let url = MeetingLink.webURL(meeting.calendarURL?.absoluteString),
              NSWorkspace.shared.open(url) else {
            operationError = "Could not open this event in Google Calendar."
            return
        }
        operationError = nil
    }

    func copyMeetingLink(_ meeting: Meeting) -> Bool {
        guard let url = MeetingLink.webURL(meeting.joinURL?.absoluteString) else {
            operationError = "This event has no valid meeting link."
            return false
        }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(url.absoluteString, forType: .string) else {
            operationError = "Could not copy the meeting link."
            return false
        }
        operationError = nil
        return true
    }

    func showEvent(_ meeting: Meeting) {
        if eventWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.minSize = NSSize(width: 580, height: 500)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("EventDetails")
            window.center()
            eventWindow = window
        }
        eventWindow?.title = meeting.title
        eventWindow?.contentView = NSHostingView(rootView: EventDetailsView(model: self, original: meeting))
        NSApp.activate(ignoringOtherApps: true)
        eventWindow?.makeKeyAndOrderFront(nil)
    }

    func closeEvent() { eventWindow?.close() }

    func prepareAgendaPreview() {
        isPreviewSession = true
        restoring = false
        let events = AgendaPreview.meetings(now: now)
        accounts = [GoogleAccount(id: "preview@example.invalid")]
        schedules.accounts["preview@example.invalid"] = AccountSchedule(
            meetings: events, selectedIDs: ["preview"], lastSync: now)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 680),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Don't Miss - Agenda preview"
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: MenuView(model: self))
        window.isReleasedWhenClosed = false
        window.center()
        agendaPreviewWindow = window
        if let first = events.first {
            showEvent(first)
            setReminder(for: first, muted: false, leadMinutes: 5)
        }
        eventWindow?.appearance = NSAppearance(named: .darkAqua)
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 600, y: screen.visibleFrame.midY - 340))
            eventWindow?.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 140, y: screen.visibleFrame.midY - 370))
        }
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func checkAgendaPreview(snapshotDirectory: URL?) throws -> Bool {
        guard let agenda = agendaPreviewWindow, let detail = eventWindow,
              agenda.isVisible, detail.isVisible,
              let agendaView = agenda.contentView, let detailView = detail.contentView,
              agendaView.bounds.width >= 440, detailView.bounds.width >= 540,
              upcoming.count == 6, let first = upcoming.first,
              eventPreferences.preference(for: first)?.leadMinutes == 5 else { return false }
        if let snapshotDirectory {
            try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
            try AgendaPreview.save(view: agendaView, to: snapshotDirectory.appendingPathComponent("agenda.png"))
            try AgendaPreview.save(view: detailView, to: snapshotDirectory.appendingPathComponent("event-details.png"))
        }
        return true
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                operationError = "Approve Don't Miss in System Settings > General > Login Items."
                SMAppService.openSystemSettingsLoginItems()
            } else { operationError = nil }
        } catch { operationError = "Login item: \(error.localizedDescription)" }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Don't Miss"
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func sleep() {
        sessionActive = false
        isDemo = false
        currentReminder = nil
        overlay.hide()
    }

    @objc private func wake() {
        sessionActive = true
        Task {
            await refresh()
            tick()
        }
    }

    @objc private func screensChanged() {
        overlay.rebuildScreens()
    }

    private struct Snapshot: Codable {
        let schedules: MultiAccountSchedule?
        let ledger: ReminderLedger
        let eventPreferences: EventReminderPreferences?
        let meetings: [Meeting]?
        let calendars: [CalendarInfo]?
        let lastSync: Date?
    }

    private var snapshotURL: URL {
        get throws {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
                .appendingPathComponent("dev.wouter.dontmiss", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            return directory.appendingPathComponent("schedule.json")
        }
    }

    private func loadSnapshot() throws {
        let url = try snapshotURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        ledger = snapshot.ledger
        eventPreferences = snapshot.eventPreferences ?? EventReminderPreferences()
        if let schedules = snapshot.schedules {
            self.schedules = schedules
        } else {
            legacySnapshot = snapshot
        }
    }

    private func migrateLegacySchedule() {
        guard let legacySnapshot else { return }
        let primaryID = legacySnapshot.calendars?.first { $0.primary == true }?.id
        guard let account = accounts.first(where: { $0.id == primaryID })
                ?? (primaryID == nil && accounts.count == 1 ? accounts.first : nil) else { return }
        let selection = UserDefaults.standard.stringArray(forKey: "selectedCalendars").map { Set($0) }
        if schedules.accounts[account.id] == nil {
            schedules.accounts[account.id] = AccountSchedule(
                calendars: legacySnapshot.calendars ?? [], meetings: legacySnapshot.meetings ?? [],
                selectedIDs: selection, lastSync: legacySnapshot.lastSync)
        }
        self.legacySnapshot = nil
    }

    private func persist() {
        if isPreviewSession { return }
        do {
            let snapshot = Snapshot(schedules: schedules, ledger: ledger, eventPreferences: eventPreferences,
                                    meetings: nil, calendars: nil, lastSync: nil)
            let url = try snapshotURL
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            storageError = nil
        } catch { storageError = "Cannot save reminder state: \(error.localizedDescription). Reminders may repeat after restart." }
    }
}
