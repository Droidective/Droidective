import Foundation

/// Runs the video editor's exports through ffmpeg (resolved via `ToolLocator`).
/// Argument construction lives in `VideoEditing` (pure, tested); this actor
/// handles tool resolution, the no-edit fast path, and process execution.
public actor VideoEditService {
    public enum EditError: Error, LocalizedError {
        case ffmpegNotFound
        case exportFailed(String)

        public var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "ffmpeg isn't installed. Run `brew install ffmpeg`, then try again."
            case .exportFailed(let reason): return reason
            }
        }
    }

    private let locator: ToolLocator

    public init(locator: ToolLocator) {
        self.locator = locator
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
        guard let ffmpeg = await locator.resolve(.ffmpeg) else { throw EditError.ffmpegNotFound }
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
        let tail = output.stderrText.split(separator: "\n").suffix(3).joined(separator: "\n")
        return tail.isEmpty ? "ffmpeg export failed." : "ffmpeg export failed:\n\(tail)"
    }
}
