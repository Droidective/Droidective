import Foundation

#if os(Windows)
import WinSDK
#elseif canImport(Glibc)
import Glibc
#endif

/// Is the process that spawned us still alive?
///
/// The daemon is a sidecar: the UI owns its lifetime and kills it on quit. When
/// the UI *crashes* instead, nothing kills it, and an orphaned daemon holds adb
/// children — the failure people experience as "adb is stuck". So the daemon
/// watches its parent and exits when it disappears.
public enum ParentWatch {
    /// - Parameter pid: the parent's process id, from `--parent-pid`.
    /// - Returns: false once the parent is gone, which is the signal to exit.
    public static func isAlive(_ pid: Int32) -> Bool {
        #if os(Windows)
        // No signals on Windows. `PROCESS_QUERY_LIMITED_INFORMATION` is the
        // least privilege that can read an exit code, and unlike the broader
        // rights it is granted across integrity levels — so this keeps working
        // when the UI runs at a different level from the daemon.
        guard let handle = OpenProcess(
            DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(bitPattern: pid))
        else { return false }
        defer { CloseHandle(handle) }
        var status: DWORD = 0
        guard GetExitCodeProcess(handle, &status) else { return false }
        // 259 is STILL_ACTIVE. A process that genuinely exits with 259 would
        // read as alive, which is why this is a liveness *hint* backed by the
        // handle open succeeding at all.
        return status == 259
        #else
        // Signal 0 performs the permission and existence checks without
        // delivering anything.
        return kill(pid, 0) == 0
        #endif
    }
}
