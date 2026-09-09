import ADBKit

/// What a debug tool's "Restart app" wipes before the relaunch: the app's
/// cache (`pm clear --cache-only` — safe, keeps you signed in) or its whole
/// data (`pm clear` — signs you out and wipes local storage, so it always
/// sits behind a confirmation). Shared by the JS Console and Reactotron
/// restart menus.
enum RestartClearScope {
    case cache
    case data
}

extension AppControlService {
    /// Run the pre-restart clear for `scope`; true when it succeeded. The
    /// caller's restart proceeds either way — a failed clear is reported in
    /// the toast, not fatal.
    func clear(_ scope: RestartClearScope, serial: String, package: String) async -> Bool {
        // No watchdog here any more: `pm clear --cache-only` never returns on
        // some images, and the bound for that now lives on the command itself
        // (`AppControlService.cacheClearTimeout`) — so the Apps hub and the
        // Quick Actions panel get it too, instead of only the two debug
        // consoles that had each wrapped their own.
        let action: AppControlService.AppAction = scope == .cache ? .clearCache : .clearData
        return (try? await control(serial: serial, packageId: package, action: action))?.ok == true
    }
}
