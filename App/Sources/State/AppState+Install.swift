import ADBKit
import AppKit
import SwiftUI

/// One APK × one device install, live or finished — the install screens render
/// these as status rows and the progress strip mirrors the running ones.
struct InstallJob: Identifiable, Equatable {
    enum Status: Equatable {
        case running
        case succeeded
        case failed(String)
    }

    let id = UUID()
    let apkURL: URL
    let serial: String
    let deviceLabel: String
    var status: Status = .running

    var apkName: String { apkURL.lastPathComponent }
    var isRunning: Bool { status == .running }
}

// MARK: - Install center

extension AppState {
    /// Route APKs opened from Finder to the opened-APK screen: surface the
    /// main window and open the `apk-open` tab (through the leave guard like
    /// every feature switch, so an APK arriving mid-recording still raises the
    /// confirmation).
    func openAPKs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        apkOpen.urls = urls
        activateMainWindow()
        requestFeature("apk-open")
    }

    /// Route a Finder-opened `.aab` to the AAB to APK feature. The converter
    /// works one bundle at a time; extras get a toast instead of silence.
    func openAABs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        pendingConvertAAB = first
        for extra in urls.dropFirst() {
            showToast(Toast(
                message: "Converting one bundle at a time — reopen \(extra.lastPathComponent) after this one",
                ok: false))
        }
        activateMainWindow()
        requestFeature("aab-convert")
    }

    /// Fire-and-forget install: the work runs in an unstructured task owned by
    /// the app — not the calling view or panel — so navigating away, closing
    /// the panel, or closing the main window never kills an `adb install`
    /// mid-flight. Feedback arrives via `installJobs`, toasts, and a macOS
    /// notification when the batch finishes in the background.
    func startInstall(_ urls: [URL], onSerials serials: [String]) {
        Task { await self.installAPKs(urls, onSerials: serials) }
    }

    /// Install one or more APKs on the given device serials, one toast per APK
    /// (failures keep the full adb output in the toast's copyText). Returns a
    /// short multi-line summary for inline display plus whether every install
    /// landed. Live per-APK×device progress rides `installJobs`.
    @discardableResult
    func installAPKs(_ urls: [URL], onSerials serials: [String]) async -> (report: String, ok: Bool) {
        guard !urls.isEmpty, !serials.isEmpty else { return ("", false) }
        InstallNotifier.requestAuthorizationOnce()
        var report: [String] = []
        var allOK = true
        await CommandLog.userInitiated {
            for url in urls {
                let name = url.lastPathComponent
                var ok = 0
                var failures: [(serial: String, result: FeatureResult)] = []
                for serial in serials {
                    let jobID = beginInstallJob(url: url, serial: serial)
                    let result = (try? await env.engine.appInstall.install(apkPath: url.path, serial: serial))
                        ?? FeatureResult(ok: false, message: "adb not found")
                    if result.ok { ok += 1 } else { failures.append((serial, result)) }
                    finishInstallJob(jobID, result: result)
                }
                if !failures.isEmpty { allOK = false }
                showToast(Self.installToast(name: name, ok: ok, total: serials.count, failures: failures))
                report.append(ok == serials.count
                    ? "Installed \(name)"
                    : "Installed \(name) on \(ok) of \(serials.count) devices")
            }
        }
        let summary = report.joined(separator: "\n")
        InstallNotifier.postIfBackgrounded(body: summary, ok: allOK)
        return (summary, allOK)
    }

    /// The progress strip's view of the running installs. Merged with
    /// `runningOperation` in RootView (an explicit operation wins — both are
    /// rare enough together that latest-wins detail isn't worth a queue).
    var installOperation: OperationStatus? {
        let running = installJobs.filter(\.isRunning)
        guard let first = running.first else { return nil }
        let label = running.count == 1
            ? "Installing \(first.apkName) on \(first.deviceLabel)…"
            : "Installing \(first.apkName) — \(running.count) installs running…"
        return OperationStatus(label: label)
    }

    private func beginInstallJob(url: URL, serial: String) -> UUID {
        let job = InstallJob(
            apkURL: url, serial: serial,
            deviceLabel: devices.first { $0.serial == serial }?.label ?? serial)
        installJobs.append(job)
        // Bounded history: drop the oldest finished entries, never a live one.
        while installJobs.count > 60, let oldest = installJobs.firstIndex(where: { !$0.isRunning }) {
            installJobs.remove(at: oldest)
        }
        return job.id
    }

    private func finishInstallJob(_ id: UUID, result: FeatureResult) {
        guard let index = installJobs.firstIndex(where: { $0.id == id }) else { return }
        installJobs[index].status = result.ok ? .succeeded : .failed(result.message)
    }

    /// A short install headline for the toast; on failure the full adb output is
    /// kept in `copyText` so the notifications panel carries the detail without
    /// dumping it into the transient toast.
    private static func installToast(
        name: String, ok: Int, total: Int, failures: [(serial: String, result: FeatureResult)]
    ) -> Toast {
        if failures.isEmpty {
            let message = total == 1 ? "Installed \(name)" : "Installed \(name) on \(total) devices"
            return Toast(message: message, ok: true)
        }
        let message = total == 1
            ? "Couldn't install \(name) — \(failures[0].result.message)"
            : "Installed \(name) on \(ok)/\(total) devices — \(failures.count) failed"
        let detail = failures
            .map { failure in
                let body = failure.result.copyText ?? failure.result.message
                return total == 1 ? body : "\(failure.serial): \(body)"
            }
            .joined(separator: "\n\n")
        return Toast(message: message, ok: false, copyText: detail.isEmpty ? nil : detail)
    }
}
