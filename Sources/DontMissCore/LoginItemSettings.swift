import Foundation
import ServiceManagement

@MainActor
public final class LoginItemSettings {
    static let configuredKey = "runAtStartupConfigured"
    public let isAvailable: Bool
    public var status: SMAppService.Status { readStatus() }

    private let defaults: UserDefaults
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    public convenience init() {
        let directories = FileManager.default.urls(for: .applicationDirectory,
                                                   in: [.localDomainMask, .userDomainMask])
        self.init(defaults: .standard,
                  isAvailable: Bundle.main.bundleIdentifier == "dev.wouter.dontmiss"
                    && Self.isInstalledApp(at: Bundle.main.bundleURL, in: directories),
                  readStatus: { SMAppService.mainApp.status },
                  register: { try SMAppService.mainApp.register() },
                  unregister: { try SMAppService.mainApp.unregister() })
    }

    init(defaults: UserDefaults, isAvailable: Bool,
         readStatus: @escaping () -> SMAppService.Status,
         register: @escaping () throws -> Void,
         unregister: @escaping () throws -> Void) {
        self.defaults = defaults
        self.isAvailable = isAvailable
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
    }

    public func applyDefault() throws {
        guard isAvailable, !defaults.bool(forKey: Self.configuredKey) else { return }
        try setEnabled(true)
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else { throw LoginError.notInstalled }
        // Attempt the migration only once, even if macOS declines registration.
        // Subsequent explicit choices and changes in System Settings take precedence.
        defaults.set(true, forKey: Self.configuredKey)
        if enabled {
            if status != .enabled && status != .requiresApproval { try register() }
            guard status == .enabled || status == .requiresApproval else { throw LoginError.enableFailed }
        } else {
            if status != .notRegistered && status != .notFound { try unregister() }
            guard status == .notRegistered || status == .notFound else { throw LoginError.disableFailed }
        }
    }

    static func isInstalledApp(at url: URL, in directories: [URL]) -> Bool {
        let app = url.standardizedFileURL.resolvingSymlinksInPath()
        guard app.pathExtension.lowercased() == "app" else { return false }
        return directories.contains {
            app.path.hasPrefix($0.standardizedFileURL.resolvingSymlinksInPath().path + "/")
        }
    }

    private enum LoginError: LocalizedError {
        case notInstalled, enableFailed, disableFailed

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                "Move Don't Miss to Applications and open it there before changing run at startup."
            case .enableFailed:
                "macOS did not enable run at startup. Try again in Settings."
            case .disableFailed:
                "macOS did not disable run at startup. Check System Settings > General > Login Items."
            }
        }
    }
}
