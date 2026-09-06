import ADBKit
import AppKit
import SwiftUI

/// One batch of files being copied onto one device by a drop.
///
/// Scoped by serial because a Mirror Wall drop is genuinely several transfers
/// at once, and a single toast can only describe the last one to finish.
struct TransferJob: Identifiable, Equatable {
    enum Status: Equatable {
        case running
        case succeeded(String)
        case failed(String)
    }

    let id = UUID()
    let serial: String
    let paths: [String]
    let destination: String
    var status: Status = .running
    /// What the batch is doing right now, for the chip's line of text.
    var stage: String = "Preparing…"
    /// Real progress for the file in flight, when its size is known. Folders
    /// and a device whose `stat` didn't answer stay indeterminate.
    var fraction: Double?
    /// The device path currently being written — what a cancel has to clean up.
    var currentRemotePath: String?
    /// The detail behind a failure, for the notifications panel.
    var detail: String?

    var isRunning: Bool { status == .running }
}

extension AppState {
    // MARK: - A drop on a device surface

    /// Carry out a drop onto one device: packages go through the install
    /// prompt (the caller owns that sheet), bundles go to the converter, and
    /// everything else starts copying immediately.
    ///
    /// The serial is the surface's own, never `targetSerials` — a wall tile
    /// and a pop-out window each mirror a device the bar isn't pointed at, and
    /// run-on-all must not turn one drop into six.
    func startDroppedCopies(_ plan: DeviceDropPlan, serial: String) {
        if !plan.bundles.isEmpty {
            openAABs(plan.bundles.map { URL(fileURLWithPath: $0) })
        }
        if !plan.copies.isEmpty {
            copyToDevice(plan.copies, toDir: plan.destination, serial: serial)
        }
    }

    /// Copy host files onto a device, tracked by a chip on whatever mirror is
    /// showing that device.
    func copyToDevice(_ paths: [String], toDir destination: String, serial: String) {
        guard !paths.isEmpty else { return }
        SystemNotifier.requestAuthorizationOnce()
        let job = TransferJob(serial: serial, paths: paths, destination: destination)
        transferJobs.append(job)
        trimTransferHistory()
        transferTasks[job.id] = Task { await runTransfer(job.id) }
    }

    /// Stop a copy and clean up the half-written file it leaves behind.
    ///
    /// Cancelling the task terminates the `adb push` child (SystemProcessRunner
    /// wraps its body in a cancellation handler), which leaves a partial file
    /// on the device — a leftover is tidiness, not correctness, so the removal
    /// is best effort.
    func cancelTransfer(_ id: UUID) {
        transferTasks[id]?.cancel()
        transferTasks[id] = nil
        guard let index = transferJobs.firstIndex(where: { $0.id == id }) else { return }
        let job = transferJobs[index]
        transferJobs[index].status = .failed("Cancelled")
        transferJobs[index].fraction = nil
        transferJobs[index].stage = "Cancelled"
        if let partial = job.currentRemotePath {
            let transfer = env.engine.transfer
            Task { await transfer.removeRemote(path: partial, serial: job.serial) }
        }
        dismissTransferLater(id, after: 3)
    }

    /// The chips a mirror of `serial` should be showing.
    func transferJobs(onSerial serial: String) -> [TransferJob] {
        transferJobs.filter { $0.serial == serial }
    }

    func installJobs(onSerial serial: String) -> [InstallJob] {
        installJobs.filter { $0.serial == serial }
    }

    // MARK: - A drop nothing claimed

    /// Send each group of a drop to the feature that owns it. The one entry
    /// point for a drag that landed on a surface with no meaning for the file
    /// — and, through `FileDropRouter`, the same table a Finder open uses.
    func routeDrop(_ dropped: [DroppedPath]) {
        let serial = targetSerials.first
        for route in FileDropRouter.routes(for: dropped, hasDevice: serial != nil) {
            switch route {
            case let .openPackages(paths):
                openPackages(paths.map { URL(fileURLWithPath: $0) })
            case let .convertBundles(paths):
                openAABs(paths.map { URL(fileURLWithPath: $0) })
            case let .openVideos(paths):
                openVideos(paths.map { URL(fileURLWithPath: $0) })
            case let .copyToDevice(paths):
                guard let serial else { continue }
                copyToDevice(paths, toDir: FileDropRouter.defaultDestination, serial: serial)
            case let .unsupported(paths):
                for path in paths {
                    showToast(Toast(
                        message: "Droidective can't open \(URL(fileURLWithPath: path).lastPathComponent)",
                        ok: false))
                }
            }
        }
    }

    // MARK: - Running one transfer

    private func runTransfer(_ id: UUID) async {
        guard let job = transferJobs.first(where: { $0.id == id }) else { return }
        let transfer = env.engine.transfer
        let poll = Task { await pollTransferProgress(id) }
        defer { poll.cancel() }

        let outcome: TransferOutcome?
        do {
            outcome = try await CommandLog.userInitiated {
                try await transfer.copyToDevice(
                    paths: job.paths, toDir: job.destination, serial: job.serial,
                    onStage: { stage in
                        Task { @MainActor [weak self] in self?.applyStage(stage, to: id) }
                    })
            }
        } catch {
            outcome = nil
            finishTransfer(id, message: (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription, ok: false, detail: nil)
        }
        guard !Task.isCancelled else { return }
        guard let outcome else { return }
        finishTransfer(id, message: outcome.summary, ok: outcome.ok, detail: outcome.detail)
    }

    private func applyStage(_ stage: DeviceTransferService.Stage, to id: UUID) {
        guard let index = transferJobs.firstIndex(where: { $0.id == id }),
              transferJobs[index].isRunning else { return }
        switch stage {
        case .preparing:
            transferJobs[index].stage = "Preparing…"
        case let .copying(name, position, total):
            transferJobs[index].stage = total == 1
                ? name
                : "\(name) — \(position) of \(total)"
            transferJobs[index].fraction = nil
            transferJobs[index].currentRemotePath = DeviceTransferService.remotePath(
                forLocal: transferJobs[index].paths[position - 1],
                inDir: transferJobs[index].destination)
        case .indexing:
            transferJobs[index].stage = "Adding to the device's library…"
            transferJobs[index].fraction = nil
            transferJobs[index].currentRemotePath = nil
        }
    }

    /// Real percentage for the file in flight: poll what the device has
    /// written against the size we already know locally. The mirror of the
    /// pull-progress trick, pointed the other way.
    private func pollTransferProgress(_ id: UUID) async {
        let transfer = env.engine.transfer
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled,
                  let job = transferJobs.first(where: { $0.id == id }), job.isRunning,
                  let remote = job.currentRemotePath,
                  let expected = Self.localFileSize(remote: remote, in: job.paths), expected > 0
            else { continue }
            let written = await transfer.remoteSize(of: remote, serial: job.serial)
            guard !Task.isCancelled,
                  let written,
                  let index = transferJobs.firstIndex(where: { $0.id == id }),
                  transferJobs[index].isRunning,
                  transferJobs[index].currentRemotePath == remote
            else { continue }
            transferJobs[index].fraction = min(1, Double(written) / Double(expected))
        }
    }

    /// The local size of whichever dropped path is landing at `remote`. nil for
    /// a folder (no single total) or an unreadable file, which keeps the chip
    /// honestly indeterminate rather than inventing a percentage.
    private static func localFileSize(remote: String, in paths: [String]) -> Int? {
        let name = URL(fileURLWithPath: remote).lastPathComponent
        guard let local = paths.first(where: { URL(fileURLWithPath: $0).lastPathComponent == name })
        else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: local, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: local)
        else { return nil }
        return attributes[.size] as? Int
    }

    private func finishTransfer(_ id: UUID, message: String, ok: Bool, detail: String?) {
        transferTasks[id] = nil
        guard let index = transferJobs.firstIndex(where: { $0.id == id }) else { return }
        transferJobs[index].status = ok ? .succeeded(message) : .failed(message)
        transferJobs[index].stage = message
        transferJobs[index].fraction = nil
        transferJobs[index].currentRemotePath = nil
        transferJobs[index].detail = detail
        showToast(Toast(message: message, ok: ok, copyText: detail))
        // A success has said its piece after a few seconds. A failure stays
        // until the next drop replaces it — the reason is the whole point.
        if ok { dismissTransferLater(id, after: 5) }
    }

    private func dismissTransferLater(_ id: UUID, after seconds: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.transferJobs.removeAll { $0.id == id }
        }
    }

    /// Bounded history: drop the oldest finished entries, never a live one.
    private func trimTransferHistory() {
        while transferJobs.count > 40,
              let oldest = transferJobs.firstIndex(where: { !$0.isRunning }) {
            transferJobs.remove(at: oldest)
        }
    }
}

// MARK: - Installing a dropped package

extension AppState {
    /// Install packages dropped on a device surface.
    ///
    /// `replacingFirst` is the override the install prompt offers: Android
    /// refuses an in-place downgrade and refuses a signature change, so the
    /// only route in those cases is uninstall-then-install — which is exactly
    /// why the prompt has to say it clears app data before the click, not
    /// after adb does.
    func installDropped(
        _ paths: [String], serial: String, packageID: String?, replacingFirst: Bool
    ) {
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard replacingFirst, let packageID else {
            startInstall(urls, onSerials: [serial], packageID: packageID)
            return
        }
        Task { @MainActor in
            let result = await CommandLog.userInitiated {
                (try? await env.engine.appControl.control(
                    serial: serial, packageId: packageID, action: .uninstall))
                    ?? FeatureResult(ok: false, message: "adb not found")
            }
            // A package that isn't there is not a reason to stop: the install
            // is the point, and "not installed" is the state Replace wanted.
            if !result.ok, !result.message.localizedCaseInsensitiveContains("not installed") {
                showToast(Toast(message: "Couldn't remove the installed copy — \(result.message)", ok: false))
            }
            startInstall(urls, onSerials: [serial], packageID: packageID)
        }
    }

    /// The recovery a failed install chip offers: take the installed copy off
    /// the device and install again. Only reachable for the failures an
    /// uninstall actually fixes (`InstallPlan.isResolvedByReplacing`) — wiping
    /// an app buys nothing against a full disk or a wrong ABI.
    func retryInstallByReplacing(_ job: InstallJob) {
        guard let packageID = job.packageID else { return }
        installJobs.removeAll { $0.id == job.id }
        installDropped(
            [job.packageURL.path], serial: job.serial,
            packageID: packageID, replacingFirst: true)
    }

    /// Whether a finished install job should offer that recovery.
    ///
    /// Reads adb's own output, not the job's friendly one-liner: the codes are
    /// what separates a signature clash (an uninstall fixes it) from a full
    /// disk (it doesn't), and `friendlyReason` has already replaced them by
    /// the time the message reaches `status`.
    static func offersReplaceRecovery(_ job: InstallJob) -> Bool {
        guard job.packageID != nil, case .failed = job.status else { return false }
        return InstallPlan.isResolvedByReplacing(job.failureOutput ?? "")
    }
}

// MARK: - The one-time drop hint

extension AppState {
    /// A mirror is streaming: show the "drop files here" hint, once ever.
    ///
    /// Nobody guesses a drop target, and nobody wants to be told twice — so it
    /// appears the first time a mirror actually streams on this Mac and never
    /// again. The `seen` flag is written the moment it is shown, so a quit in
    /// the middle can't replay it.
    func showMirrorDropHintOnce() {
        guard !UserDefaults.standard.bool(forKey: mirrorDropHintSeenKey) else { return }
        UserDefaults.standard.set(true, forKey: mirrorDropHintSeenKey)
        mirrorDropHintVisible = true
        mirrorDropHintTask?.cancel()
        mirrorDropHintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.mirrorDropHintVisible = false
        }
    }
}

// MARK: - Pop-out mirror windows

extension AppState {
    /// The registry bookkeeping a pop-out mirror needs before `openWindow`.
    ///
    /// A `WindowGroup(for:)` persists its presented value and re-presents it at
    /// the next launch, so a mirror window has to have been *asked for* in this
    /// session or it comes up as a phantom (see `MirrorWindowHost`). Every
    /// opener — the control bar, a wall tile, the Window menu, the device bar —
    /// records the request through here.
    func prepareMirrorWindow(serial: String) {
        core.mirrorWindowOwner = id
        core.noteMirrorWindowRequested(serial)
    }
}
