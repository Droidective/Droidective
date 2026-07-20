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

    /// React Native apps ship on Android and iOS, so the role spans both —
    /// booted simulators join the device bar and the launch lists.
    @Test func reactNativeSeesBothPlatforms() {
        #expect(FeatureRegistry.visiblePlatforms(for: .reactNativeDeveloper) == [.android, .iosSimulator])
    }

    /// The RN role curates the iOS-side tools too: the simulator log stream
    /// and the Simulate hub (which carries the iOS-only push tester).
    @Test func reactNativeCuratesIOSTools() {
        let ids = FeatureRegistry.featureIDs(for: .reactNativeDeveloper)
        #expect(ids.contains("ios-logs"))
        #expect(ids.contains("simulate"))
    }

    @Test(arguments: [
        UserRole.androidDeveloper, .qaTester, .supportTriage, .securityTester,
    ])
    func androidOnlyRolesSeeOnlyAndroid(role: UserRole) {
        #expect(FeatureRegistry.visiblePlatforms(for: role) == [.android])
    }

    @Test func emulatorsRenamesPerRole() throws {
        let emulators = try #require(FeatureRegistry.byID["emulators"])
        #expect(FeatureRegistry.presented(emulators, for: nil).title == "Emulators & Simulators")
        #expect(FeatureRegistry.presented(emulators, for: .iosDeveloper).title == "Simulators")
        // Both platforms visible → the combined default title stands.
        #expect(FeatureRegistry.presented(emulators, for: .reactNativeDeveloper).title == "Emulators & Simulators")
        for role in UserRole.allCases where role != .iosDeveloper && role != .reactNativeDeveloper {
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
