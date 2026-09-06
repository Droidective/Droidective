import Foundation

/// The result of copying one batch of files to a device.
public struct TransferOutcome: Sendable, Equatable {
    public var copied: Int
    public var total: Int
    /// One message per file that didn't land, in the order they were tried.
    public var failures: [String]
    public var destination: String

    public init(copied: Int, total: Int, failures: [String], destination: String) {
        self.copied = copied
        self.total = total
        self.failures = failures
        self.destination = destination
    }

    public var ok: Bool { failures.isEmpty && copied == total }

    /// The headline for a toast or a chip.
    public var summary: String {
        if ok {
            return total == 1
                ? "Copied to \(destination)"
                : "Copied \(copied) files to \(destination)"
        }
        if copied == 0 {
            return failures.first ?? "Nothing was copied"
        }
        return "Copied \(copied) of \(total) — \(failures.count) failed"
    }

    /// The full detail, kept off the toast and handed to the notifications
    /// panel the way install failures already are.
    public var detail: String? { failures.isEmpty ? nil : failures.joined(separator: "\n") }
}

/// Copying host files onto a device: make the destination, push, then ask
/// MediaStore to index what landed.
///
/// `adb push` rides the sync protocol — no device shell, so the local and
/// remote paths need no quoting. Every *other* step here (`mkdir`, `stat`,
/// `rm`, the media scan) does cross `adb shell` carrying a file name that came
/// straight from Finder, so each one quotes.
public struct DeviceTransferService: Sendable {
    /// What the copy is doing right now, for the progress chip.
    public enum Stage: Sendable, Equatable {
        case preparing
        case copying(name: String, index: Int, total: Int)
        case indexing
    }

    let client: AdbClient

    public init(client: AdbClient) {
        self.client = client
    }

    /// The device path a local file lands on.
    public static func remotePath(forLocal localPath: String, inDir dir: String) -> String {
        let name = URL(fileURLWithPath: localPath).lastPathComponent
        let base = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
        return base + "/" + name
    }

    public func copyToDevice(
        paths: [String],
        toDir dir: String,
        serial: String,
        onStage: @Sendable @escaping (Stage) -> Void = { _ in }
    ) async throws(AdbError) -> TransferOutcome {
        guard !paths.isEmpty else {
            return TransferOutcome(copied: 0, total: 0, failures: [], destination: dir)
        }
        onStage(.preparing)
        // A destination that isn't there yet is a silent `adb push` failure,
        // and /sdcard/Download is missing on a freshly wiped emulator.
        _ = try await client.run(on: serial, ["shell", "mkdir", "-p", shellQuote(dir)])
        let sdk = await sdkLevel(serial: serial)

        var copied = 0
        var failures: [String] = []
        var landed: [String] = []
        for (index, path) in paths.enumerated() {
            let name = URL(fileURLWithPath: path).lastPathComponent
            onStage(.copying(name: name, index: index + 1, total: paths.count))
            let remote = Self.remotePath(forLocal: path, inDir: dir)
            let result = try await client.run(
                on: serial, ["push", path, remote], timeout: .seconds(600))
            if result.succeeded {
                copied += 1
                landed.append(remote)
            } else {
                failures.append("\(name): \(friendlyAdbError(result, fallback: "couldn't be copied"))")
            }
        }

        if !landed.isEmpty {
            onStage(.indexing)
            for remote in landed {
                // Best effort by design: an unindexed file is still on the
                // device, so a scan that fails must not fail the copy.
                _ = try? await client.run(on: serial, MediaScan.command(sdk: sdk, path: remote))
            }
        }
        return TransferOutcome(
            copied: copied, total: paths.count, failures: failures, destination: dir)
    }

    /// Bytes already written on the device, for a real percentage while a push
    /// runs. The mirror of the pull-progress trick: poll the growing side
    /// against the size we already know. nil when the file isn't there yet or
    /// the device's `stat` didn't answer with a number.
    public func remoteSize(of path: String, serial: String) async -> Int? {
        guard let result = try? await client.run(
            on: serial, ["shell", "stat", "-c", "%s", shellQuote(path)], timeout: .seconds(10)
        ), result.succeeded else { return nil }
        let text = result.stdout
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return text.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap(Int.init)
    }

    /// Clean up the partial file a cancelled copy left behind. Best effort —
    /// the copy is already over, and a leftover is a tidiness problem, not a
    /// correctness one.
    public func removeRemote(path: String, serial: String) async {
        _ = try? await client.run(on: serial, ["shell", "rm", "-f", shellQuote(path)])
    }

    private func sdkLevel(serial: String) async -> Int? {
        guard let value = try? await DeviceProps.get(
            client: client, serial: serial, "ro.build.version.sdk"
        ) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespaces))
    }
}
