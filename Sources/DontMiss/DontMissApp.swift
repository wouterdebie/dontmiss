import SwiftUI

@main
struct DontMissApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: delegate.model)
        } label: {
            MenuLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuLabel: View {
    @ObservedObject var model: AppModel

    private var needsAttention: Bool { model.errors != nil || model.stale }

    var body: some View {
        Label {
            Text("Don't Miss")
        } icon: {
            if let image = needsAttention ? MenuBarIcon.attention : MenuBarIcon.regular {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Image(systemName: needsAttention ? "bell.badge" : "bell.fill")
            }
        }
        .labelStyle(.iconOnly)
        .help(needsAttention ? "Don't Miss - calendar needs attention" : "Don't Miss")
        .accessibilityValue(needsAttention ? "Calendar needs attention" : "")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--smoke-menubar-icon") {
            let passed = MenuBarIcon.checkResources()
            print(passed ? "PASS: normal and attention menu-bar templates load at all three resolutions." : "FAIL: menu-bar icon resources.")
            model.stop()
            exit(passed ? 0 : 1)
        }
        if arguments.contains("--smoke-updater") {
            var overrides = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            overrides["SUEnableAutomaticChecks"] = false
            UserDefaults.standard.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
            model.updates.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
                let updates = model.updates
                let passed = updates.started && updates.canCheck && !updates.automaticChecks && updates.error == nil
                print(passed ? "PASS: Sparkle starts, manual checks are available, and automatic checks are off." : "FAIL: \(updates.error ?? "Updater state is invalid")")
                model.stop()
                exit(passed ? 0 : 1)
            }
            return
        }
        if arguments.contains("--smoke-agenda") {
            model.prepareAgendaPreview()
            Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(2))
                    let snapshotDirectory: URL?
                    if let index = arguments.firstIndex(of: "--snapshot-directory"),
                       arguments.indices.contains(index + 1) {
                        snapshotDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                    } else { snapshotDirectory = nil }
                    let passed = try model.checkAgendaPreview(snapshotDirectory: snapshotDirectory)
                    print(passed ? "PASS: agenda, event details and local reminder controls." : "FAIL: agenda preview.")
                    model.stop()
                    exit(passed ? 0 : 1)
                } catch {
                    print("FAIL: \(error.localizedDescription)")
                    model.stop()
                    exit(1)
                }
            }
            return
        }
        if arguments.contains("--smoke-test") {
            model.testAlert()
            Task { @MainActor in
                try await Task.sleep(for: .seconds(2))
                let passed = model.smokeTestPassed()
                print(passed ? "PASS: one full-screen overlay with native behind-window blur on the selected display." : "FAIL: active-display overlay or blur configuration.")
                model.stop()
                exit(passed ? 0 : 1)
            }
            return
        }
        model.start { [weak self] in
            guard let self else { return }
            if let index = arguments.firstIndex(of: "--import-oauth"), arguments.indices.contains(index + 1) {
                model.importConfiguration(from: URL(fileURLWithPath: arguments[index + 1]))
            }
            if arguments.contains("--connect-google"), model.clientConfigured {
                Task { await model.connect() }
            }
            if arguments.contains("--test-alert") {
                model.testAlert()
            } else if !model.connected || arguments.contains("--settings") {
                model.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
