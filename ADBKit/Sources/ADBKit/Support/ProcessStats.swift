#if canImport(Darwin)
import Darwin
#endif
import Foundation

/// Reads the current process's own resource usage — cumulative CPU time and
/// physical memory footprint — via `proc_pid_rusage`, for `ResourceWatchdog`.
public enum ProcessStats {
    #if canImport(Darwin)
    /// Seconds per mach absolute-time tick, from the host timebase.
    private static let machTickSeconds: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    /// A snapshot of this process's usage, or nil if the kernel call fails.
    public static func sample() -> ResourceSample? {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0 else { return nil }
        return ResourceSample(
            uptime: ProcessInfo.processInfo.systemUptime,
            cpuTimeSeconds: Double(info.ri_user_time + info.ri_system_time) * machTickSeconds,
            footprintBytes: info.ri_phys_footprint
        )
    }
    #else
    /// Self-usage sampling is a Darwin kernel call (`proc_pid_rusage`); other
    /// hosts report nothing and the watchdog stays quiet.
    public static func sample() -> ResourceSample? { nil }
    #endif
}
