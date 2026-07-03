#if DEBUG
import ADBKit
import Observation
import SwiftUI

/// Debug-only HUD: samples Droidective's *own* memory, CPU, and network
/// throughput once a second and drives the top-left overlay. Compiled only into
/// Debug builds. Memory and CPU come from `ProcessStats` (CPU% derived from the
/// cumulative-time delta, the same math `ResourceWatchdog` uses); network from
/// `NetworkTrafficMeter`, the app's own transfer tally.
@MainActor
@Observable
final class DevMetricsMonitor {
    private(set) var memoryBytes: UInt64 = 0
    private(set) var cpuPercent: Double = 0
    private(set) var downBytesPerSec: Double = 0
    private(set) var upBytesPerSec: Double = 0

    private var poller: Task<Void, Never>?
    private var lastCPU: (uptime: TimeInterval, seconds: Double)?
    private var lastNet: (uptime: TimeInterval, totals: NetworkTrafficMeter.Totals)?

    func start(interval: Duration = .seconds(1)) {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        poller?.cancel()
        poller = nil
    }

    private func sample() {
        guard let s = ProcessStats.sample() else { return }
        memoryBytes = s.footprintBytes
        if let prev = lastCPU, s.uptime > prev.uptime {
            let used = max(0, s.cpuTimeSeconds - prev.seconds)
            cpuPercent = used / (s.uptime - prev.uptime) * 100
        }
        lastCPU = (s.uptime, s.cpuTimeSeconds)

        let totals = NetworkTrafficMeter.shared.totals()
        if let prev = lastNet, s.uptime > prev.uptime {
            let dt = s.uptime - prev.uptime
            downBytesPerSec = Double(totals.received.subtractingClamped(prev.totals.received)) / dt
            upBytesPerSec = Double(totals.sent.subtractingClamped(prev.totals.sent)) / dt
        }
        lastNet = (s.uptime, totals)
    }
}

private extension UInt64 {
    /// Delta against an earlier cumulative reading, floored at zero so a counter
    /// reset or wrap never shows as a spurious huge spike.
    func subtractingClamped(_ other: UInt64) -> UInt64 { self >= other ? self - other : 0 }
}

/// The floating panel. Non-interactive so it can never intercept a click on the
/// UI beneath it; hidden entirely when the Settings toggle is off. Its own
/// monitor instance, started on appear.
struct DevMetricsOverlay: View {
    @AppStorage(DevMetrics.overlayEnabledKey) private var enabled = true
    @State private var monitor = DevMetricsMonitor()

    var body: some View {
        Group {
            if enabled {
                panel
                    .onAppear { monitor.start() }
                    .onDisappear { monitor.stop() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 3) {
            metric("MEM", DevMetrics.formatBytes(monitor.memoryBytes))
            metric("CPU", String(format: "%.1f%%", monitor.cpuPercent))
            metric("NET", "↓\(DevMetrics.formatRate(monitor.downBytesPerSec))  ↑\(DevMetrics.formatRate(monitor.upBytesPerSec))")
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.white.opacity(0.5))
            Text(value).monospacedDigit()
        }
    }
}

/// Shared constants and formatting for the debug metrics overlay, outside the
/// `View`/monitor so the Settings toggle can reach the same defaults key.
enum DevMetrics {
    /// UserDefaults key backing the Settings ▸ Appearance toggle. On by default,
    /// so a fresh Debug build shows the overlay without any setup.
    static let overlayEnabledKey = "showDevMetricsOverlay"

    static func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1_024
            ? String(format: "%.2f GB", mb / 1_024)
            : String(format: "%.0f MB", mb)
    }

    static func formatRate(_ bytesPerSec: Double) -> String {
        let rate = max(0, bytesPerSec)
        switch rate {
        case ..<1_024: return String(format: "%.0f B/s", rate)
        case ..<1_048_576: return String(format: "%.1f KB/s", rate / 1_024)
        default: return String(format: "%.1f MB/s", rate / 1_048_576)
        }
    }
}
#endif
