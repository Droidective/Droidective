import Testing

@testable import ADBKit

@Suite struct SidebarVisibilityTests {
    // MARK: Plain mode switch (Settings ▸ Appearance)

    @Test func enteringAutoHideRestsWithTheOverlayHidden() {
        // Auto-hide means hidden-until-peek, so switching it on never reveals the
        // overlay — regardless of whether the pinned sidebar was showing.
        #expect(SidebarVisibility.afterModeChange(autoHide: true, fixedVisible: true).overlayShown == false)
        #expect(SidebarVisibility.afterModeChange(autoHide: true, fixedVisible: false).overlayShown == false)
    }

    @Test func leavingAutoHideAlwaysRestoresThePinnedSidebar() {
        let next = SidebarVisibility.afterModeChange(autoHide: false, fixedVisible: false)
        #expect(next.fixedVisible == true)
        #expect(next.overlayShown == false)
    }

    // MARK: Device-bar button

    @Test func buttonRevealsThePinnedSidebarWhenItWasEvicted() {
        // The bug: a split-resize left the pinned sidebar hidden in fixed mode.
        // The click brings it back and stays in fixed mode — no dead first click,
        // no surprise mode flip.
        let next = SidebarVisibility.afterButtonPress(autoHide: false, fixedVisible: false)
        #expect(next == (autoHide: false, fixedVisible: true, overlayShown: false))
    }

    @Test func buttonSwitchesAVisiblePinnedSidebarToAutoHide() {
        let next = SidebarVisibility.afterButtonPress(autoHide: false, fixedVisible: true)
        #expect(next == (autoHide: true, fixedVisible: true, overlayShown: false))
    }

    @Test func buttonReturnsFromAutoHideToAShownPinnedSidebar() {
        #expect(
            SidebarVisibility.afterButtonPress(autoHide: true, fixedVisible: false)
                == (autoHide: false, fixedVisible: true, overlayShown: false)
        )
        #expect(
            SidebarVisibility.afterButtonPress(autoHide: true, fixedVisible: true)
                == (autoHide: false, fixedVisible: true, overlayShown: false)
        )
    }
}
