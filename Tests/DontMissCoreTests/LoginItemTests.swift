import Foundation
import ServiceManagement
import Testing
@testable import DontMissCore

@MainActor
struct LoginItemTests {
    private enum TestError: Error { case denied }

    @MainActor
    private final class Service {
        var status: SMAppService.Status = .notRegistered
        var registrationResult: SMAppService.Status = .enabled
        var registrationFails = false
        var unregistrationFails = false
        var registrations = 0
        var unregistrations = 0

        func register() throws {
            registrations += 1
            if registrationFails { throw TestError.denied }
            status = registrationResult
        }

        func unregister() throws {
            unregistrations += 1
            if unregistrationFails { throw TestError.denied }
            status = .notRegistered
        }
    }

    @MainActor
    private struct Fixture {
        let name = "LoginItemTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let service = Service()

        init() throws {
            defaults = try #require(UserDefaults(suiteName: name))
        }

        func settings(available: Bool = true) -> LoginItemSettings {
            LoginItemSettings(defaults: defaults, isAvailable: available,
                              readStatus: { service.status },
                              register: { try service.register() },
                              unregister: { try service.unregister() })
        }

        func cleanup() { defaults.removePersistentDomain(forName: name) }
    }

    @Test func enablesOnceForNewAndExistingInstallations() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        // Pre-existing preferences do not suppress the explicitly requested migration.
        fixture.defaults.set(5, forKey: "leadMinutes")
        try fixture.settings().applyDefault()
        #expect(fixture.service.status == .enabled)
        #expect(fixture.service.registrations == 1)
        try fixture.settings().applyDefault()
        #expect(fixture.service.registrations == 1)
    }

    @Test func explicitOptOutSurvivesRestart() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let settings = fixture.settings()
        try settings.applyDefault()
        try settings.setEnabled(false)
        let restoredDefaults = try #require(UserDefaults(suiteName: fixture.name))
        #expect(restoredDefaults.bool(forKey: LoginItemSettings.configuredKey))
        try fixture.settings().applyDefault()
        #expect(fixture.service.status == .notRegistered)
        #expect(fixture.service.registrations == 1)
        #expect(fixture.service.unregistrations == 1)
        try settings.setEnabled(true)
        #expect(fixture.service.status == .enabled)
        #expect(fixture.service.registrations == 2)
    }

    @Test func constructionHasNoLoginItemSideEffects() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let settings = fixture.settings()
        #expect(settings.status == .notRegistered)
        #expect(fixture.service.registrations == 0)
        #expect(fixture.defaults.object(forKey: LoginItemSettings.configuredKey) == nil)
    }

    @Test func optingOutBeforeDefaultIsAppliedIsRespected() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.settings().setEnabled(false)
        try fixture.settings().applyDefault()
        #expect(fixture.service.registrations == 0)
        #expect(fixture.service.unregistrations == 0)
    }

    @Test func systemSettingsChangesAreNotOverridden() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let settings = fixture.settings()
        try settings.applyDefault()
        fixture.service.status = .requiresApproval
        #expect(settings.status == .requiresApproval)
        try fixture.settings().applyDefault()
        #expect(fixture.service.registrations == 1)
        fixture.service.status = .notRegistered
        try fixture.settings().applyDefault()
        #expect(fixture.service.status == .notRegistered)
        #expect(fixture.service.registrations == 1)
    }

    @Test func existingRegistrationAndApprovalAreNotRepeated() throws {
        for status in [SMAppService.Status.enabled, .requiresApproval] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            fixture.service.status = status
            try fixture.settings().applyDefault()
            try fixture.settings().setEnabled(true)
            #expect(fixture.service.status == status)
            #expect(fixture.service.registrations == 0)
        }
    }

    @Test func approvalRequiredAfterRegistrationIsExposed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.service.registrationResult = .requiresApproval
        let settings = fixture.settings()
        try settings.applyDefault()
        #expect(settings.status == .requiresApproval)
        try settings.setEnabled(false)
        #expect(settings.status == .notRegistered)
        #expect(fixture.service.unregistrations == 1)
    }

    @Test func registrationFailureIsReportedWithoutRepeatedAutomaticAttempts() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.service.registrationFails = true
        #expect(throws: TestError.denied) { try fixture.settings().applyDefault() }
        try fixture.settings().applyDefault()
        #expect(fixture.service.registrations == 1)
        fixture.service.registrationFails = false
        try fixture.settings().setEnabled(true)
        #expect(fixture.service.status == .enabled)
        #expect(fixture.service.registrations == 2)
    }

    @Test func ineffectiveRegistrationAndUnregistrationFailuresAreReported() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.service.registrationResult = .notFound
        #expect(throws: (any Error).self) { try fixture.settings().applyDefault() }
        fixture.service.status = .enabled
        fixture.service.unregistrationFails = true
        #expect(throws: TestError.denied) { try fixture.settings().setEnabled(false) }
        #expect(fixture.service.status == .enabled)
    }

    @Test func uninstalledCopiesDoNotRegisterOrConsumeTheDefault() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.settings(available: false).applyDefault()
        #expect(fixture.defaults.object(forKey: LoginItemSettings.configuredKey) == nil)
        #expect(throws: (any Error).self) { try fixture.settings(available: false).setEnabled(true) }
        #expect(fixture.service.registrations == 0)
        try fixture.settings().applyDefault()
        #expect(fixture.service.status == .enabled)
    }

    @Test func onlyInstalledAppBundlesAreEligible() {
        let directories = ["/Applications", "/Users/example/Applications"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        for path in ["/Applications/Don't Miss.app", "/Applications/Tools/Don't Miss.app",
                     "/Users/example/Applications/Don't Miss.app"] {
            #expect(LoginItemSettings.isInstalledApp(at: URL(fileURLWithPath: path), in: directories))
        }
        for path in ["/Volumes/Don't Miss/Don't Miss.app", "/tmp/dist/Don't Miss.app",
                     "/Applications-other/Don't Miss.app", "/Applications/DontMiss",
                     "/Applications/../Downloads/Don't Miss.app", "/tmp/.build/debug/DontMiss"] {
            #expect(!LoginItemSettings.isInstalledApp(at: URL(fileURLWithPath: path), in: directories))
        }
    }
}
