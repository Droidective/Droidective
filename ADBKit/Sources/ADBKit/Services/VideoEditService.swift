import Foundation

/// Runs the video editor's exports through ffmpeg. The app bundles a static
/// ffmpeg, so `bundledPath` is normally used; a `ToolLocator` lookup is a
/// fallback if the bundled binary is somehow missing. Argument construction
/// lives in `VideoEditing` (pure, tested); this actor handles tool resolution,
/// the no-edit fast path, and process execution.
public actor VideoEditService {
    public enum EditError: Error, LocalizedError {
        case ffmpegNotFound
        case exportFailed(String)

        public var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "ffmpeg is missing from the app bundle."
            case .exportFailed(let reason): return reason
            }
        }
    }

    private let locator: ToolLocator
    private let bundledPath: String?

    /// - Parameter bundledPath: absolute path to the bundled ffmpeg (from the
    ///   App layer's `BundledTools`); preferred over a system install.
    public init(locator: ToolLocator, bundledPath: String? = nil) {
        self.locator = locator
        self.bundledPath = bundledPath
    }

    /// Bundled ffmpeg first, then a system install as a fallback.
    private func ffmpegPath() async -> String? {
        if let bundledPath, FileManager.default.isExecutableFile(atPath: bundledPath) {
            return bundledPath
        }
        return await locator.resolve(.ffmpeg)
    }

    /// A still-frame PNG preview of `source`, or nil if it can't be produced.
    /// Uses ffmpeg because AVAssetImageGenerator refuses the recorder's remuxed
    /// H.264 (error -11821), even though the file plays and re-encodes fine.
    public func thumbnail(of source: URL) async -> Data? {
        guard let ffmpeg = await ffmpegPath() else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("droidective-thumb-\(UInt32.random(in: 0 ... 0xffff_ffff)).png")
        defer { try? FileManager.default.removeItem(at: out) }
        let result = await SystemProcessRunner().run(
            executable: ffmpeg,
            arguments: VideoEditing.thumbnailArguments(input: source.path, output: out.path),
            timeout: .seconds(30), maxOutputBytes: 1024 * 1024)
        guard result.exitCode == 0 else { return nil }
        return try? Data(contentsOf: out)
    }

    /// An MP4 of `source` that AVFoundation can open, written to a temp file —
    /// nil when ffmpeg is missing or both conversions fail.
    ///
    /// Only for inputs the player has already refused. The editor accepts
    /// every container ffmpeg demuxes (`VideoInputFormat`), but playback,
    /// scrubbing and AVKit's trim UI are all AVFoundation, which opens a
    /// fraction of that list — so an `.mkv` would otherwise load as a black
    /// pane with the trim button permanently disabled.
    ///
    /// A remux is tried first and is nearly free (`-c copy`, a file copy's
    /// worth of work) — it covers the common case of H.264 in a container
    /// AVFoundation won't parse. Only if that still won't play does the codec
    /// itself need converting.
    ///
    /// The proxy is for *playing*. Exports always run from the original, so
    /// nothing here costs the saved file any quality — and trim points chosen
    /// against the proxy carry over unchanged, since both share one timeline.
    public func playableProxy(for source: URL, isPlayable: @Sendable (URL) async -> Bool) async -> URL? {
        guard let ffmpeg = await ffmpegPath() else { return nil }
        let remuxed = proxyURL(for: source)
        if await run(ffmpeg, VideoEditing.remuxArguments(input: source.path, output: remuxed.path)),
           await isPlayable(remuxed) {
            return remuxed
        }
        try? FileManager.default.removeItem(at: remuxed)

        let transcoded = proxyURL(for: source)
        if await run(ffmpeg, VideoEditing.transcodeArguments(input: source.path, output: transcoded.path)),
           await isPlayable(transcoded) {
            return transcoded
        }
        try? FileManager.default.removeItem(at: transcoded)
        return nil
    }

    /// Always `.mp4` whatever went in — the container AVFoundation is
    /// certain to parse. The name keeps the source's for the rare case
    /// someone finds one of these in the temp directory.
    private func proxyURL(for source: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "droidective-proxy-\(base)-\(UInt32.random(in: 0 ... 0xffff_ffff))")
            .appendingPathExtension("mp4")
    }

    /// A transcode of a long recording is minutes of work, so this shares the
    /// export timeout rather than the thumbnail's.
    private func run(_ ffmpeg: String, _ arguments: [String]) async -> Bool {
        let output = await SystemProcessRunner().run(
            executable: ffmpeg, arguments: arguments,
            timeout: .seconds(600), maxOutputBytes: 4 * 1024 * 1024
        )
        return output.exitCode == 0
    }

    /// Apply `options` to `source` and write `destination`. A no-edit export to
    /// the same container is a lossless file copy; everything else re-encodes.
    public func export(
        source: URL,
        options: VideoExportOptions,
        to destination: URL
    ) async throws -> URL {
        if options.isIdentity, source.pathExtension.lowercased() == options.format.fileExtension {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
        guard let ffmpeg = await ffmpegPath() else { throw EditError.ffmpegNotFound }
        let args = VideoEditing.ffmpegArguments(
            input: source.path, output: destination.path, options: options
        )
        let output = await SystemProcessRunner().run(
            executable: ffmpeg,
            arguments: args,
            timeout: .seconds(600),
            maxOutputBytes: 4 * 1024 * 1024
        )
        guard output.exitCode == 0 else { throw EditError.exportFailed(failureMessage(output)) }
        return destination
    }

    private func failureMessage(_ output: ProcessOutput) -> String {
        if output.timedOut { return "Export timed out." }
        let tail = VideoEditing.stderrTail(output.stderrText)
        return tail.isEmpty ? "ffmpeg export failed." : "ffmpeg export failed:\n\(tail)"
    }
}
