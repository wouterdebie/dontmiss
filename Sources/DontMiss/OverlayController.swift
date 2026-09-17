import AppKit
import SwiftUI
import DontMissCore

enum OverlayAction { case dismiss, snooze, join }

@MainActor
private final class AlertContent: ObservableObject {
    @Published var meeting: Meeting
    @Published var queued: Int
    @Published var error: String?
    let action: (OverlayAction) -> Void

    init(meeting: Meeting, queued: Int, action: @escaping (OverlayAction) -> Void) {
        self.meeting = meeting
        self.queued = queued
        self.action = action
    }
}

private final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayController {
    private var panels: [NSPanel] = []
    private var content: AlertContent?
    private var previousApp: NSRunningApplication?
    private var targetDisplayID: NSNumber?
    var isVisible: Bool { !panels.isEmpty }
    var coversSelectedScreen: Bool {
        guard panels.count == 1, let panel = panels.first,
              let backdrop = panel.contentView as? NSVisualEffectView,
              let screen = NSScreen.screens.first(where: { displayID($0) == targetDisplayID }) else {
            print("FAIL: reminder window, blur view or selected display is missing; panel count=\(panels.count).")
            return false
        }
        let passed = panel.isVisible && panel.frame == screen.frame && panel.level == .screenSaver
            && panel.collectionBehavior.contains(.canJoinAllSpaces)
            && panel.collectionBehavior.contains(.fullScreenAuxiliary)
            && !panel.isOpaque && panel.backgroundColor == .clear
            && backdrop.blendingMode == .behindWindow && backdrop.state == .active
            && backdrop.material == .hudWindow
        if !passed {
            print("FAIL: reminder state: visible=\(panel.isVisible), frame=\(panel.frame), screen=\(screen.frame), level=\(panel.level.rawValue), behavior=\(panel.collectionBehavior.rawValue), opaque=\(panel.isOpaque), background=\(panel.backgroundColor), blending=\(backdrop.blendingMode.rawValue), state=\(backdrop.state.rawValue), material=\(backdrop.material.rawValue).")
        }
        return passed
    }

    func show(_ meeting: Meeting, queued: Int, action: @escaping (OverlayAction) -> Void) {
        previousApp = NSWorkspace.shared.frontmostApplication
        targetDisplayID = nil
        content = AlertContent(meeting: meeting, queued: queued) { [weak self] actionType in
            // Joining should leave focus with the browser/conferencing app.
            if case .join = actionType { self?.previousApp = nil }
            action(actionType)
        }
        rebuildScreens()
    }

    func update(_ meeting: Meeting, queued: Int) {
        content?.meeting = meeting
        content?.queued = queued
    }

    func showError(_ text: String) { content?.error = text }

    func rebuildScreens() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        guard let content, let screen = targetScreen() else { return }
        let panel = AlertPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.setFrame(screen.frame, display: true)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        // isFloatingPanel resets the level, so set our overlay level afterward.
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingView(rootView: AlertView(content: content))
        hosting.frame = backdrop.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        backdrop.addSubview(hosting)
        panel.contentView = backdrop
        panel.orderFrontRegardless()
        panels.append(panel)
        panels.first?.makeKey()
        NSLog("Don't Miss: showing one reminder window; %d display(s) connected", NSScreen.screens.count)
    }

    private func displayID(_ screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        // Keep the alert on its original display, unless that display is disconnected.
        if let targetDisplayID, let existing = screens.first(where: { displayID($0) == targetDisplayID }) {
            return existing
        }
        let fallback = screens.firstIndex { $0 == NSScreen.main }
        guard let index = ActiveDisplay.index(frames: screens.map(\.frame), pointer: NSEvent.mouseLocation,
                                              fallback: fallback) else { return nil }
        targetDisplayID = displayID(screens[index])
        return screens[index]
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        content = nil
        targetDisplayID = nil
        let foreground = NSWorkspace.shared.frontmostApplication
        if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier,
           foreground?.processIdentifier == previousApp.processIdentifier
            || foreground?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        previousApp = nil
    }
}

private struct AlertView: View {
    @ObservedObject var content: AlertContent

    var body: some View {
        ZStack {
            ReminderPalette.ink.opacity(0.22).ignoresSafeArea()
            VStack(spacing: 24) {
                AppIconView(size: 80)
                Text("DON'T MISS").font(.headline).tracking(5).foregroundStyle(ReminderPalette.secondaryText)
                Text(content.meeting.title)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.4)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(ceil(content.meeting.start.timeIntervalSince(context.date)))
                    Text(seconds > 0 ? "Starts in \(seconds / 60):\(String(format: "%02d", seconds % 60))"
                         : "Started \(abs(seconds) / 60)m ago")
                        .font(.system(size: 32, weight: .medium, design: .monospaced))
                        .foregroundStyle(ReminderPalette.gradient(for: .dark))
                        .accessibilityLabel(seconds > 0 ? "Starts in \(seconds) seconds" : "Meeting has started")
                }
                Text("\(content.meeting.start.formatted(date: .omitted, time: .shortened)) - \(content.meeting.end.formatted(date: .omitted, time: .shortened))  |  \(content.meeting.calendarName)")
                    .font(.title3).foregroundStyle(ReminderPalette.secondaryText)
                HStack(spacing: 16) {
                    if content.meeting.joinURL != nil {
                        Button { content.action(.join) } label: {
                            Text("Join meeting").foregroundStyle(ReminderPalette.ink)
                        }
                        .buttonStyle(.borderedProminent).tint(ReminderPalette.blue)
                    }
                    Button("Snooze 1 minute") { content.action(.snooze) }.buttonStyle(.bordered)
                    Button("Dismiss") { content.action(.dismiss) }
                        .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                }
                .controlSize(.large).font(.title3)
                if content.queued > 0 {
                    Text("\(content.queued) more reminder(s) waiting").foregroundStyle(ReminderPalette.secondaryText)
                }
                if let error = content.error { Text(error).foregroundStyle(.red) }
                Text("Esc to dismiss").font(.caption).foregroundStyle(ReminderPalette.secondaryText)
            }
            .padding(48).frame(maxWidth: 1000)
        }
        .foregroundStyle(ReminderPalette.text)
        .tint(ReminderPalette.blue)
        .preferredColorScheme(.dark)
    }
}
