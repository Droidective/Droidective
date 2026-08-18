import Foundation
import Testing
@testable import ADBKit

@Suite struct WorkspaceRegistryTests {
    private let w1 = WorkspaceID("w1")
    private let w2 = WorkspaceID("w2")
    private let w3 = WorkspaceID("w3")

    private func registry(_ pairs: [(WorkspaceID, String?, Set<String>)]) -> WorkspaceRegistry {
        var registry = WorkspaceRegistry()
        for (id, serial, features) in pairs {
            registry.setDevice(serial: serial, for: id)
            registry.setOpenFeatures(features, for: id)
        }
        return registry
    }

    // MARK: - Registration and ordering

    @Test func registerIsIdempotent() {
        var registry = WorkspaceRegistry()
        registry.register(w1)
        registry.register(w1)
        #expect(registry.count == 1)
    }

    @Test func ordinalFollowsCreationOrder() {
        var registry = WorkspaceRegistry()
        registry.register(w1)
        registry.register(w2)
        #expect(registry.ordinal(of: w1) == 1)
        #expect(registry.ordinal(of: w2) == 2)
        #expect(registry.ordinal(of: w3) == nil)
    }

    @Test func removingAWindowRenumbersTheRest() {
        var registry = WorkspaceRegistry()
        registry.register(w1)
        registry.register(w2)
        registry.register(w3)
        registry.remove(w1)
        #expect(registry.ordinal(of: w2) == 1)
        #expect(registry.ordinal(of: w3) == 2)
    }

    @Test func settingADeviceRegistersAnUnknownWindow() {
        var registry = WorkspaceRegistry()
        registry.setDevice(serial: "abc", for: w1)
        #expect(registry.count == 1)
        #expect(registry[w1]?.serial == "abc")
    }

    @Test func labelIsTheOrdinalAndTracksRenumbering() {
        var registry = WorkspaceRegistry()
        registry.register(w1)
        registry.register(w2)
        #expect(registry.label(of: w1) == "Window 1")
        #expect(registry.label(of: w2) == "Window 2")
        registry.remove(w1)
        #expect(registry.label(of: w2) == "Window 1")
    }

    @Test func labelOfAnUnknownWindowIsNeverEmpty() {
        #expect(WorkspaceRegistry().label(of: w1) == "another window")
    }

    // MARK: - Device ownership

    @Test func deviceOwnerIgnoresTheAskingWindow() {
        let registry = self.registry([(w1, "abc", []), (w2, "def", [])])
        #expect(registry.owner(ofDevice: "abc", excluding: w1) == nil)
        #expect(registry.owner(ofDevice: "abc", excluding: w2) == w1)
        #expect(registry.owner(ofDevice: "ghi") == nil)
    }

    @Test func selectingADeviceAnotherWindowHoldsIsAConflict() {
        let registry = self.registry([(w1, "abc", []), (w2, nil, [])])
        #expect(registry.conflict(selecting: "abc", in: w2) == .deviceOwnedElsewhere(w1))
        #expect(registry.conflict(selecting: "abc", in: w1) == nil)
        #expect(registry.conflict(selecting: "def", in: w2) == nil)
    }

    @Test func unclaimedSkipsDevicesAlreadyShownSomewhere() {
        let registry = self.registry([(w1, "abc", []), (w2, "def", [])])
        #expect(registry.unclaimed(from: ["abc", "def", "ghi"]) == ["ghi"])
        #expect(registry.unclaimed(from: []).isEmpty)
    }

    // MARK: - Exclusive features

    @Test func mirrorAndConsoleAreExclusiveButLogcatIsNot() {
        #expect(WorkspaceRegistry.isExclusive("scrcpy"))
        #expect(WorkspaceRegistry.isExclusive("screen-record"))
        #expect(WorkspaceRegistry.isExclusive("js-console"))
        #expect(WorkspaceRegistry.isExclusive("frida-console"))
        #expect(!WorkspaceRegistry.isExclusive("logcat"))
        #expect(!WorkspaceRegistry.isExclusive("apps"))
        // The Reactotron relay is one app-wide listener shared by every
        // window on purpose — it must never be treated as exclusive.
        #expect(!WorkspaceRegistry.isExclusive("reactotron"))
    }

    /// A typo'd id would silently disable the conflict rule it names — the
    /// window would race the other one instead of offering Focus / Take over.
    /// `scrcpy-window` is the pop-out mirror's pseudo-id, not a registry entry.
    @Test func everyExclusiveIDIsARealFeature() {
        for id in WorkspaceRegistry.exclusiveFeatureIDs where id != "scrcpy-window" {
            #expect(FeatureRegistry.byID[id] != nil, "\(id) is not a registry feature")
        }
    }

    // MARK: - Claims (the Mirror Wall's tiles and the pop-out mirror windows)

    /// A wall streams up to six devices, and a pop-out mirror window shows a
    /// device its owner window isn't pointed at, so both can only be seen
    /// through claims — the exclusivity rules read them like an open tab.
    @Test func aClaimMakesAnotherWindowSeeTheFeatureAsTaken() {
        var registry = self.registry([(w1, "abc", []), (w2, "def", [])])
        registry.setClaims([.init(featureID: "scrcpy-window", serial: "def")], for: w1)
        #expect(registry.owner(ofFeature: "scrcpy-window", on: "def", excluding: w2) == w1)
        #expect(registry.owner(ofFeature: "scrcpy-window", on: "ghi", excluding: w2) == nil)
    }

    @Test func claimsAreReplacedNotAccumulated() {
        var registry = self.registry([(w1, "abc", [])])
        registry.setClaims([.init(featureID: "mirror-wall", serial: "def")], for: w1)
        registry.setClaims([.init(featureID: "mirror-wall", serial: "ghi")], for: w1)
        #expect(registry.owner(ofMirroredDevice: "def", excluding: w2) == nil)
        #expect(registry.owner(ofMirroredDevice: "ghi", excluding: w2) == w1)
    }

    @Test func aWindowIsNotBlockedByItsOwnClaims() {
        var registry = self.registry([(w1, "abc", [])])
        registry.setClaims([.init(featureID: "mirror-wall", serial: "def")], for: w1)
        #expect(registry.owner(ofMirroredDevice: "def", excluding: w1) == nil)
    }

    /// All three routes to the live mirror drive one device-side session, so a
    /// wall tile asks about the family, not about its own id.
    @Test func everyRouteToTheMirrorClaimsTheDeviceForTheFamily() {
        var registry = self.registry([(w1, "abc", ["scrcpy"]), (w2, "def", [])])
        #expect(registry.owner(ofMirroredDevice: "abc", excluding: w2) == w1)

        registry.setClaims([.init(featureID: "scrcpy-window", serial: "ghi")], for: w1)
        #expect(registry.owner(ofMirroredDevice: "ghi", excluding: w2) == w1)

        registry.setClaims([.init(featureID: "mirror-wall", serial: "jkl")], for: w1)
        #expect(registry.owner(ofMirroredDevice: "jkl", excluding: w2) == w1)
    }

    @Test func aNonMirrorFeatureDoesNotClaimTheDeviceForMirroring() {
        var registry = self.registry([(w1, "abc", ["logcat"]), (w2, "def", [])])
        #expect(registry.owner(ofMirroredDevice: "abc", excluding: w2) == nil)
        registry.setClaims([.init(featureID: "js-console", serial: "ghi")], for: w1)
        #expect(registry.owner(ofMirroredDevice: "ghi", excluding: w2) == nil)
    }

    @Test func everyMirrorFamilyIDIsRealOrThePopOutPseudoID() {
        for id in WorkspaceRegistry.mirrorFeatureIDs where id != "scrcpy-window" {
            #expect(FeatureRegistry.byID[id] != nil, "\(id) is not a registry feature")
        }
    }

    /// The wall contends per tile, so it must NOT take the whole-pane
    /// Focus / Take Over banner over the window's selected device — that would
    /// block five working tiles because of the sixth.
    @Test func theWallIsNotBlockedAsAWhole() {
        var registry = self.registry([(w1, "abc", ["mirror-wall"]), (w2, "abc", [])])
        registry.setClaims([.init(featureID: "mirror-wall", serial: "abc")], for: w1)
        #expect(!WorkspaceRegistry.isExclusive("mirror-wall"))
        #expect(registry.conflict(opening: "mirror-wall", in: w2) == nil)
    }

    @Test func exclusiveFeatureOnTheSameDeviceConflicts() {
        let registry = self.registry([(w1, "abc", ["scrcpy"]), (w2, "abc", [])])
        #expect(registry.conflict(opening: "scrcpy", in: w2)
            == .featureOwnedElsewhere(w1, featureID: "scrcpy"))
    }

    @Test func exclusiveFeatureOnADifferentDeviceIsFine() {
        let registry = self.registry([(w1, "abc", ["scrcpy"]), (w2, "def", [])])
        #expect(registry.conflict(opening: "scrcpy", in: w2) == nil)
    }

    @Test func nonExclusiveFeaturesNeverConflict() {
        let registry = self.registry([(w1, "abc", ["logcat"]), (w2, "abc", [])])
        #expect(registry.conflict(opening: "logcat", in: w2) == nil)
        #expect(registry.owner(ofFeature: "logcat", on: "abc", excluding: w2) == nil)
    }

    @Test func aWindowNeverConflictsWithItself() {
        let registry = self.registry([(w1, "abc", ["scrcpy"])])
        #expect(registry.conflict(opening: "scrcpy", in: w1) == nil)
    }

    @Test func aWindowWithNoDeviceHasNoConflicts() {
        let registry = self.registry([(w1, "abc", ["scrcpy"]), (w2, nil, [])])
        #expect(registry.conflict(opening: "scrcpy", in: w2) == nil)
    }

    @Test func conflictClearsWhenTheOwnerClosesTheFeature() {
        var registry = self.registry([(w1, "abc", ["scrcpy"]), (w2, "abc", [])])
        #expect(registry.conflict(opening: "scrcpy", in: w2) != nil)
        registry.setOpenFeatures([], for: w1)
        #expect(registry.conflict(opening: "scrcpy", in: w2) == nil)
    }

    @Test func conflictClearsWhenTheOwnerSwitchesDevice() {
        var registry = self.registry([(w1, "abc", ["scrcpy"]), (w2, "abc", [])])
        registry.setDevice(serial: "def", for: w1)
        #expect(registry.conflict(opening: "scrcpy", in: w2) == nil)
    }

    @Test func conflictClearsWhenTheOwnerWindowCloses() {
        var registry = self.registry([(w1, "abc", ["scrcpy"]), (w2, "abc", [])])
        registry.remove(w1)
        #expect(registry.conflict(opening: "scrcpy", in: w2) == nil)
    }

    @Test func threeWindowsReportTheFirstOwner() {
        var registry = self.registry([
            (w1, "abc", ["js-console"]), (w2, "abc", ["js-console"]), (w3, "abc", []),
        ])
        #expect(registry.conflict(opening: "js-console", in: w3)
            == .featureOwnedElsewhere(w1, featureID: "js-console"))
        registry.remove(w1)
        #expect(registry.conflict(opening: "js-console", in: w3)
            == .featureOwnedElsewhere(w2, featureID: "js-console"))
    }

    // MARK: - Window tint

    /// The app has one accent; only the *extra* windows take a color, so
    /// opening a second window never repaints the first.
    @Test func theFirstWindowKeepsTheAppAccent() {
        #expect(WorkspaceRegistry.tintIndex(ofWindow: 1, paletteSize: 6) == nil)
        #expect(WorkspaceRegistry.tintIndex(ofWindow: 2, paletteSize: 6) == 0)
        #expect(WorkspaceRegistry.tintIndex(ofWindow: 3, paletteSize: 6) == 1)
    }

    @Test func extraWindowsGetDistinctTintsUntilThePaletteWraps() {
        let indexes = (2...7).map { WorkspaceRegistry.tintIndex(ofWindow: $0, paletteSize: 6) }
        #expect(indexes == [0, 1, 2, 3, 4, 5])
        // The seventh window is the first to reuse a color.
        #expect(WorkspaceRegistry.tintIndex(ofWindow: 8, paletteSize: 6) == 0)
    }

    @Test func tintHandlesADegenerateOrdinalOrPalette() {
        #expect(WorkspaceRegistry.tintIndex(ofWindow: 2, paletteSize: 0) == nil)
        #expect(WorkspaceRegistry.tintIndex(ofWindow: 0, paletteSize: 6) == nil)
    }

    // MARK: - WorkspaceID

    @Test func generatedIDsAreUnique() {
        let ids = (0..<64).map { _ in WorkspaceID.generate() }
        #expect(Set(ids).count == 64)
    }

    @Test func workspaceIDRoundTripsAsABareString() throws {
        let encoded = try JSONEncoder().encode(WorkspaceID("abc-123"))
        #expect(String(data: encoded, encoding: .utf8) == "\"abc-123\"")
        #expect(try JSONDecoder().decode(WorkspaceID.self, from: encoded) == WorkspaceID("abc-123"))
    }
}
