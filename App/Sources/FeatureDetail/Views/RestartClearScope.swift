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
        switch scope {
        case .cache:
            return await clearCacheBounded(serial: serial, package: package)
        case .data:
            return (try? await control(serial: serial, packageId: package, action: .clearData))?.ok
                == true
        }
    }

    /// `pm clear --cache-only` never returns on some images (observed live on
    /// the API 36 emulator), so the cache clear gets a bounded window —
    /// cancelling the task kills the adb child. A full data clear doesn't need
    /// this: `pm clear` returns reliably.
    private func clearCacheBounded(serial: String, package: String) async -> Bool {
        let clear = Task {
            (try? await control(serial: serial, packageId: package, action: .clearCache))?.ok == true
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(10))
            clear.cancel()
        }
        let ok = await clear.value
        watchdog.cancel()
        return ok
    }
}
