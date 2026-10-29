import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The installable package formats, for the drop zones and open panels that
/// accept them. `AppPackageFormat` in ADBKit is the single source of truth for
/// the list — a format added there widens every entry point at once.
enum InstallablePackage {
    /// Content types for an `NSOpenPanel`. The extensions are declared in the
    /// app's Info.plist, so each resolves to the declared type.
    static var contentTypes: [UTType] {
        AppPackageFormat.fileExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    /// The installable files out of a drop, in the order they arrived.
    static func filter(_ urls: [URL]) -> [URL] {
        urls.filter { AppPackageFormat.detect(fileName: $0.lastPathComponent) != nil }
    }
}

/// One package × one device install, live or finished — the install screens
/// render these as status rows and the progress strip mirrors the running ones.
struct InstallJob: Identifiable, Equatable {
    enum Status: Equatable {
        case running
        case succeeded
        case failed(String)
    }

    let id = UUID()
    let packageURL: URL
    let serial: String
    let deviceLabel: String
    var status: Status = .running
    /// What a split-bundle install is doing right now (unpacking, copying an
    /// expansion file…). Nil for a plain APK, which has only one step.
    var stage: String?
    /// The package this APK installs, when it was read before the install (the
    /// drop prompt reads it). It is what an "Uninstall & Install" recovery
    /// removes, so a failure without it can't offer that button.
    var packageID: String?
    /// adb's own output for a failure, kept because `status` carries the
    /// friendly one-liner and the recovery check needs the `INSTALL_FAILED_*`
    /// code to tell a signature clash from a full disk.
    var failureOutput: String?
    /// Whether the install was asked to open the app afterwards, so the
    /// "Uninstall & Install" recovery asks the same.
    var opensApp = false

    var packageName: String { packageURL.lastPathComponent }
    var isRunning: Bool { status == .running }
}

/// How one package's install went across its target devices.
private struct PackageInstallOutcome {
    var installed = 0
    var failures: [(serial: String, result: FeatureResult)] = []
    /// Why the app couldn't be opened on a device it installed on, when
    /// opening was asked for — the first such reason, for one toast.
    var openFailure: String?
}

// MARK: - Install center

extension AppState {
    /// Route packages opened from Finder to the opened-package screen: surface
    /// the main window and open the `apk-open` tab (through the leave guard
    /// like every feature switch, so a file arriving mid-recording still raises
    /// the confirmation).
    func openPackages(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        apkOpen.urls = urls
        activateMainWindow()
        requestFeature("apk-open")
    }

    /// Load an APK into APK Studio on its Inspect tab — offered beside an
    /// install, by the package screens, for plain APKs only: the studio works
    /// on one APK and can't read a bundle container.
    func openInApkStudio(_ url: URL) {
        apkStudio.apk = url
        apkStudio.signInput = nil
        apkStudio.tab = .inspect
        requestFeature("apk-studio")
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

    /// Route a Finder-opened video to the Video Editor. Unlike `apk-open`,
    /// this needs no tab of its own: `video-editor` is already a registry
    /// feature with a route, so the file is staged and the feature requested —
    /// which also means it inherits the route tests instead of the string
    /// branch `apk-open` has to live with.
    ///
    /// One at a time, because the editor edits one video: extras say so
    /// rather than being dropped silently, matching `openAABs`.
    func openVideos(_ urls: [URL]) {
        guard let first = urls.first else { return }
        pendingVideo = first
        for extra in urls.dropFirst() {
            showToast(Toast(
                message: "Editing one video at a time — reopen \(extra.lastPathComponent) after this one",
                ok: false))
        }
        activateMainWindow()
        requestFeature("video-editor")
    }

    /// Take the staged Finder-opened video, clearing it so it opens once.
    func claimPendingVideo() -> URL? {
        defer { pendingVideo = nil }
        return pendingVideo
    }

    /// Fire-and-forget install: the work runs in an unstructured task owned by
    /// the app — not the calling view or panel — so navigating away, closing
    /// the panel, or closing the main window never kills an `adb install`
    /// mid-flight. Feedback arrives via `installJobs`, toasts, and a macOS
    /// notification when the batch finishes in the background.
    func startInstall(
        _ urls: [URL], onSerials serials: [String], packageID: String? = nil, opensApp: Bool = false
    ) {
        Task { await self.installAPKs(urls, onSerials: serials, packageID: packageID, opensApp: opensApp) }
    }

    /// Install one or more packages on the given device serials, one toast per
    /// package (failures keep the full adb output in the toast's copyText).
    /// Returns a short multi-line summary for inline display plus whether every
    /// install landed. Live per-package×device progress rides `installJobs`.
    ///
    /// APKs go straight to `adb install`; `.apks`/`.xapk`/`.apkm` bundles are
    /// unpacked and narrowed to this device's splits first — see
    /// `AppBundleInstallService`. `opensApp` launches the app on each device
    /// it landed on, which is what the install screens' "Open after
    /// installing" box asks for.
    @discardableResult
    func installAPKs(
        _ urls: [URL], onSerials serials: [String], packageID: String? = nil, opensApp: Bool = false
    ) async -> (report: String, ok: Bool) {
        guard !urls.isEmpty, !serials.isEmpty else { return ("", false) }
        SystemNotifier.requestAuthorizationOnce()
        var report: [String] = []
        var allOK = true
        await CommandLog.userInitiated {
            for url in urls {
                let name = url.lastPathComponent
                let outcome = await installPackage(
                    url, onSerials: serials, packageID: packageID, opensApp: opensApp)
                if !outcome.failures.isEmpty { allOK = false }
                showToast(Self.installToast(
                    name: name, ok: outcome.installed, total: serials.count, failures: outcome.failures,
                    opened: opensApp && outcome.openFailure == nil))
                if let reason = outcome.openFailure {
                    showToast(Toast(message: "Installed \(name). \(reason)", ok: false))
                }
                report.append(outcome.installed == serials.count
                    ? "Installed \(name)"
                    : "Installed \(name) on \(outcome.installed) of \(serials.count) devices")
            }
        }
        let summary = report.joined(separator: "\n")
        SystemNotifier.postIfBackgrounded(
            title: allOK ? "Install finished" : "Install failed",
            body: summary.isEmpty ? (allOK ? "The app was installed." : "The install didn't complete.") : summary,
            sound: !allOK)
        return (summary, allOK)
    }

    /// One package onto every target, then — when asked — opened on each one
    /// it reached. The package name is read while the first install runs, so
    /// opening never waits on aapt2 afterwards.
    private func installPackage(
        _ url: URL, onSerials serials: [String], packageID: String?, opensApp: Bool
    ) async -> PackageInstallOutcome {
        let identity = opensApp ? packageIdentity(of: url, known: packageID) : nil
        var outcome = PackageInstallOutcome()
        for serial in serials {
            let jobID = beginInstallJob(url: url, serial: serial, packageID: packageID, opensApp: opensApp)
            let result = await install(url, on: serial, jobID: jobID)
            if result.ok {
                outcome.installed += 1
                if let identity {
                    updateInstallJob(jobID, stage: "Opening the app…")
                    let opened = await openInstalledApp(await identity.value, on: serial)
                    if !opened.ok, outcome.openFailure == nil { outcome.openFailure = opened.message }
                }
            } else {
                outcome.failures.append((serial, result))
            }
            finishInstallJob(jobID, result: result)
        }
        return outcome
    }

    /// The package a file installs: the one the caller already read, or read
    /// now without the signer check, which only the details card shows.
    private func packageIdentity(of url: URL, known: String?) -> Task<String?, Never> {
        let reader = env.engine.packageDetails
        return Task {
            if let known { return known }
            return await reader.details(packagePath: url.path, readsSigning: false)?.packageName
        }
    }

    private func openInstalledApp(_ packageID: String?, on serial: String) async -> FeatureResult {
        guard let packageID else {
            return FeatureResult(
                ok: false, message: "Couldn't open it — reading its package name needs the SDK build-tools.")
        }
        return (try? await env.engine.appControl.control(serial: serial, packageId: packageID, action: .open))
            ?? FeatureResult(ok: false, message: "Couldn't open it — adb not found.")
    }

    /// One package onto one device, with the bundle installer's stage feeding
    /// the job's live status line. A thrown error is a host-side refusal (an
    /// unreadable archive, no matching ABI, a missing tool) and carries its own
    /// message; adb's own rejections come back as a failed result instead.
    private func install(_ url: URL, on serial: String, jobID: UUID) async -> FeatureResult {
        do {
            // Weak on the *outer* closure: it's the escaping one the installer
            // holds for the length of the install, so a weak capture only on
            // the inner Task retained self anyway.
            return try await env.engine.bundleInstall.install(
                bundlePath: url.path, serial: serial
            ) { [weak self] stage in
                Task { @MainActor in
                    self?.updateInstallJob(jobID, stage: Self.stageLabel(stage))
                }
            }
        } catch {
            // Both BundleError and AdbError carry an actionable message; a
            // file-system error from the unpack directory falls back to its own.
            return FeatureResult(
                ok: false,
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// A short, present-tense label for the install's current step. Nil for the
    /// plain single-APK install, whose row already says "Installing".
    private static func stageLabel(_ stage: AppBundleInstallService.Stage) -> String? {
        switch stage {
        case .unpacking: "Unpacking the archive…"
        case .readingDevice: "Checking the device…"
        case .installing(let count): count > 1 ? "Installing \(count) split APKs…" : nil
        case .pushingExpansion(let name, let index, let total):
            "Copying \(name) (\(index) of \(total))…"
        }
    }

    /// The progress strip's view of the running installs. Merged with
    /// `runningOperation` in RootView (an explicit operation wins — both are
    /// rare enough together that latest-wins detail isn't worth a queue).
    var installOperation: OperationStatus? {
        let running = installJobs.filter(\.isRunning)
        guard let first = running.first else { return nil }
        let label = running.count == 1
            ? first.stage ?? "Installing \(first.packageName) on \(first.deviceLabel)…"
            : "Installing \(first.packageName) — \(running.count) installs running…"
        return OperationStatus(label: label)
    }

    private func beginInstallJob(url: URL, serial: String, packageID: String?, opensApp: Bool) -> UUID {
        var job = InstallJob(
            packageURL: url, serial: serial,
            deviceLabel: devices.first { $0.serial == serial }?.label ?? serial)
        job.packageID = packageID
        job.opensApp = opensApp
        installJobs.append(job)
        // Bounded history: drop the oldest finished entries, never a live one.
        while installJobs.count > 60, let oldest = installJobs.firstIndex(where: { !$0.isRunning }) {
            installJobs.remove(at: oldest)
        }
        return job.id
    }

    private func updateInstallJob(_ id: UUID, stage: String?) {
        guard let index = installJobs.firstIndex(where: { $0.id == id }), installJobs[index].isRunning else { return }
        installJobs[index].stage = stage
    }

    private func finishInstallJob(_ id: UUID, result: FeatureResult) {
        guard let index = installJobs.firstIndex(where: { $0.id == id }) else { return }
        installJobs[index].status = result.ok ? .succeeded : .failed(result.message)
        installJobs[index].failureOutput = result.ok ? nil : (result.copyText ?? result.message)
        installJobs[index].stage = nil
        // A success row has said its piece after a few seconds — drop it so
        // the install screens don't carry a stale green check forever.
        // Failures stay: the user needs the reason until a retry replaces it.
        if result.ok {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.installJobs.removeAll { $0.id == id }
            }
        }
    }

    /// A short install headline for the toast; on failure the full adb output is
    /// kept in `copyText` so the notifications panel carries the detail without
    /// dumping it into the transient toast.
    private static func installToast(
        name: String, ok: Int, total: Int, failures: [(serial: String, result: FeatureResult)], opened: Bool
    ) -> Toast {
        // postsSystemNotification is off: the batch posts one summary
        // notification instead of one per APK.
        if failures.isEmpty {
            let verb = opened ? "Installed and opened" : "Installed"
            let message = total == 1 ? "\(verb) \(name)" : "\(verb) \(name) on \(total) devices"
            return Toast(message: message, ok: true, postsSystemNotification: false)
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
        return Toast(
            message: message, ok: false, copyText: detail.isEmpty ? nil : detail,
            postsSystemNotification: false)
    }
}
