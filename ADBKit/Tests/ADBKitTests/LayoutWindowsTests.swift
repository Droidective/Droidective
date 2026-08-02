import Foundation
import Testing
@testable import ADBKit

/// `LayoutState`'s per-window state and the one-time migration off the legacy
/// single-workspace fields.
@Suite struct LayoutWindowsTests {
    private func legacyLayout() -> LayoutState {
        LayoutState(
            favorites: ["logcat"],
            tabGroups: [
                TabGroupState(tabs: ["home", "logcat"], activeTab: "logcat"),
                TabGroupState(tabs: ["scrcpy"], activeTab: "scrcpy"),
            ],
            focusedGroup: 1,
            terminalResumeDirs: ["/tmp/a", "/tmp/b"]
        )
    }

    // MARK: - Migration

    @Test func migrationFoldsTheLegacyWorkspaceIntoOneWindow() {
        var layout = legacyLayout()
        let changed1 = layout.adoptWindows(serial: "abc", bundleId: "com.acme")
        #expect(changed1)
        let windows = try! #require(layout.windows)
        #expect(windows.count == 1)
        #expect(windows[0].serial == "abc")
        #expect(windows[0].bundleId == "com.acme")
        #expect(windows[0].tabGroups?.count == 2)
        #expect(windows[0].tabGroups?[0].tabs == ["home", "logcat"])
        #expect(windows[0].focusedGroup == 1)
        #expect(windows[0].terminalResumeDirs == ["/tmp/a", "/tmp/b"])
    }

    @Test func migrationClearsTheLegacyFieldsSoTheyCantBeReadTwice() {
        var layout = legacyLayout()
        _ = layout.adoptWindows(serial: nil, bundleId: nil)
        #expect(layout.tabGroups == nil)
        #expect(layout.focusedGroup == nil)
        #expect(layout.terminalResumeDirs == nil)
    }

    @Test func migrationLeavesAppWidePreferencesAlone() {
        var layout = legacyLayout()
        layout.enabledIds = ["logcat", "apps"]
        layout.sidebarOrder = ["apps", "logcat"]
        layout.selectedRole = UserRole.reactNativeDeveloper.rawValue
        _ = layout.adoptWindows(serial: nil, bundleId: nil)
        #expect(layout.enabledIds == ["logcat", "apps"])
        #expect(layout.sidebarOrder == ["apps", "logcat"])
        #expect(layout.selectedRole == UserRole.reactNativeDeveloper.rawValue)
        #expect(layout.favorites == ["logcat"])
    }

    @Test func migrationIsIdempotent() {
        var layout = legacyLayout()
        let changed2 = layout.adoptWindows(serial: "abc", bundleId: nil)
        #expect(changed2)
        let first = layout.windows
        let changed3 = layout.adoptWindows(serial: "def", bundleId: nil)
        #expect(!changed3)
        #expect(layout.windows == first)
    }

    @Test func aBrandNewLayoutMigratesToOneEmptyWindow() {
        var layout = LayoutState()
        let changed4 = layout.adoptWindows(serial: nil, bundleId: nil)
        #expect(changed4)
        #expect(layout.windows?.count == 1)
        #expect(layout.windows?[0].tabGroups == nil)
        #expect(layout.windows?[0].serial == nil)
    }

    @Test func anEmptyWindowsArrayIsRepairedNotTrusted() {
        var layout = LayoutState()
        layout.windows = []
        let changed5 = layout.adoptWindows(serial: "abc", bundleId: nil)
        #expect(changed5)
        #expect(layout.windows?.count == 1)
        #expect(layout.windows?[0].serial == "abc")
    }

    @Test func legacyFieldsWrittenByAnOlderBuildAreDroppedNotReadopted() {
        // An older build can round-trip the file and re-emit the legacy keys
        // alongside the new `windows`. They must never overwrite per-window
        // state that has moved on since.
        var layout = LayoutState()
        _ = layout.adoptWindows(serial: "abc", bundleId: nil)
        let migrated = layout.windows
        layout.tabGroups = [TabGroupState(tabs: ["home"], activeTab: "home")]
        layout.terminalResumeDirs = ["/stale"]
        let changed6 = layout.adoptWindows(serial: "abc", bundleId: nil)
        #expect(changed6)
        #expect(layout.windows == migrated)
        #expect(layout.tabGroups == nil)
        #expect(layout.terminalResumeDirs == nil)
    }

    // MARK: - Upsert / remove

    @Test func upsertAppendsNewWindowsAndReplacesKnownOnes() {
        var layout = LayoutState()
        let a = WorkspaceID("a")
        let b = WorkspaceID("b")
        layout.upsertWindow(WindowState(id: a, serial: "one"))
        layout.upsertWindow(WindowState(id: b, serial: "two"))
        #expect(layout.windows?.map(\.id) == [a, b])
        layout.upsertWindow(WindowState(id: a, serial: "changed"))
        #expect(layout.windows?.map(\.id) == [a, b], "replacing must not reorder")
        #expect(layout.window(a)?.serial == "changed")
    }

    @Test func removingAWindowKeepsTheOrderOfTheRest() {
        var layout = LayoutState()
        let ids = ["a", "b", "c"].map(WorkspaceID.init)
        for id in ids { layout.upsertWindow(WindowState(id: id)) }
        layout.removeWindow(ids[1])
        #expect(layout.windows?.map(\.id) == [ids[0], ids[2]])
    }

    @Test func theLastWindowIsNeverRemoved() {
        // Closing the last window must leave its tabs on disk — that's what the
        // next launch reopens.
        var layout = LayoutState()
        let a = WorkspaceID("a")
        layout.upsertWindow(WindowState(
            id: a, tabGroups: [TabGroupState(tabs: ["home", "logcat"], activeTab: "logcat")]))
        layout.removeWindow(a)
        #expect(layout.windows?.count == 1)
        #expect(layout.window(a)?.tabGroups?[0].tabs == ["home", "logcat"])
    }

    @Test func removingAnUnknownWindowChangesNothing() {
        var layout = LayoutState()
        layout.upsertWindow(WindowState(id: WorkspaceID("a")))
        layout.upsertWindow(WindowState(id: WorkspaceID("b")))
        layout.removeWindow(WorkspaceID("zzz"))
        #expect(layout.windows?.count == 2)
    }

    @Test func windowLookupMissesCleanly() {
        var layout = LayoutState()
        #expect(layout.window(WorkspaceID("a")) == nil)
        layout.upsertWindow(WindowState(id: WorkspaceID("a")))
        #expect(layout.window(WorkspaceID("b")) == nil)
    }

    // MARK: - Codable

    @Test func windowsRoundTripThroughJSON() throws {
        var layout = LayoutState(favorites: [])
        layout.upsertWindow(WindowState(
            id: WorkspaceID("w-1"),
            serial: "emulator-5554",
            bundleId: "com.acme.app",
            tabGroups: [TabGroupState(tabs: ["home", "logcat"], activeTab: "logcat")],
            focusedGroup: 0,
            terminalResumeDirs: ["/Users/x/proj"]
        ))
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        #expect(decoded == layout)
        #expect(decoded.window(WorkspaceID("w-1"))?.serial == "emulator-5554")
    }

    @Test func aLayoutFileWrittenBeforeMultiWindowStillDecodes() throws {
        let json = """
        {"favorites":["logcat"],"tabGroups":[{"tabs":["home"],"activeTab":"home"}],\
        "focusedGroup":0,"terminalResumeDirs":["/tmp"]}
        """
        var layout = try JSONDecoder().decode(LayoutState.self, from: Data(json.utf8))
        #expect(layout.windows == nil)
        let changed7 = layout.adoptWindows(serial: "abc", bundleId: nil)
        #expect(changed7)
        #expect(layout.windows?[0].tabGroups?[0].tabs == ["home"])
        #expect(layout.windows?[0].terminalResumeDirs == ["/tmp"])
    }
}
