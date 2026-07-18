import Testing
@testable import ADBKit

/// Role-scoped platform visibility: which device platforms a role sees, and
/// how the emulators screen renames itself to match.
@Suite struct RolePresentationTests {
    @Test func iosDeveloperSeesOnlySimulators() {
        #expect(FeatureRegistry.visiblePlatforms(for: .iosDeveloper) == [.iosSimulator])
    }

    @Test func nilRoleSeesBothPlatforms() {
        #expect(FeatureRegistry.visiblePlatforms(for: nil) == [.android, .iosSimulator])
    }

    @Test(arguments: [
        UserRole.androidDeveloper, .reactNativeDeveloper, .qaTester, .supportTriage, .securityTester,
    ])
    func everyNonIOSRoleSeesOnlyAndroid(role: UserRole) {
        #expect(FeatureRegistry.visiblePlatforms(for: role) == [.android])
    }

    @Test func emulatorsRenamesPerRole() throws {
        let emulators = try #require(FeatureRegistry.byID["emulators"])
        #expect(FeatureRegistry.presented(emulators, for: nil).title == "Emulators & Simulators")
        #expect(FeatureRegistry.presented(emulators, for: .iosDeveloper).title == "Simulators")
        for role in UserRole.allCases where role != .iosDeveloper {
            #expect(FeatureRegistry.presented(emulators, for: role).title == "Emulators")
        }
    }

    @Test func presentationNeverChangesIdentityOrBehavior() throws {
        let emulators = try #require(FeatureRegistry.byID["emulators"])
        for role in UserRole.allCases {
            let adapted = FeatureRegistry.presented(emulators, for: role)
            #expect(adapted.id == emulators.id)
            #expect(adapted.kind == emulators.kind)
            #expect(adapted.icon == emulators.icon)
            #expect(adapted.platforms == emulators.platforms)
        }
    }

    @Test func nonEmulatorsDefsAreUntouched() throws {
        let logcat = try #require(FeatureRegistry.byID["logcat"])
        #expect(FeatureRegistry.presented(logcat, for: .iosDeveloper).title == logcat.title)
        #expect(FeatureRegistry.presented(logcat, for: .iosDeveloper).subtitle == logcat.subtitle)
    }
}
