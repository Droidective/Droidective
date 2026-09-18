import ADBKit
import Foundation

/// Wire shapes for the video editor.
///
/// The daemon owns ffmpeg and nothing else here: `VideoEditing` already turns
/// export options into an argument vector, pure and tested in ADBKit, and both
/// apps go through it so a rotation or a trim cannot mean two different things.
///
/// **Which proxy to build is the client's call.** The Mac asks AVFoundation
/// whether a file plays and steps remux → transcode until one does
/// (`VideoEditService.playableProxy`); the daemon cannot ask a webview that, so
/// the webview asks for each step in turn. The ladder is the same and the
/// decision sits with the thing that can actually answer it.
public enum VideoProtocol {
    /// Every container the editor opens, for the open panel and the drop filter.
    public struct FormatsResponse: Codable, Equatable, Sendable {
        public let extensions: [String]
        public init(extensions: [String]) { self.extensions = extensions }
    }

    /// The wire spelling of `VideoEditService.ProxyMode`, which is what
    /// actually chooses the arguments.
    public typealias ProxyMode = VideoEditService.ProxyMode

    public struct ProxyRequest: Codable, Equatable, Sendable {
        public let path: String
        public let mode: ProxyMode
        public init(path: String, mode: ProxyMode) {
            self.path = path
            self.mode = mode
        }
    }

    public struct ProxyResponse: Codable, Equatable, Sendable {
        /// Where the playable MP4 landed. The client reads it and, when it is
        /// done with the editor, asks for it to be removed.
        public let path: String
        public init(path: String) { self.path = path }
    }

    /// The edit, as the client holds it. Mirrors `VideoExportOptions` field for
    /// field rather than inventing a second vocabulary — ADBKit's type is what
    /// builds the arguments, so anything renamed here would silently stop
    /// applying.
    public struct ExportOptions: Codable, Equatable, Sendable {
        public var trimStart: Double?
        public var trimEnd: Double?
        public var rotationDegrees: Int
        public var flipH: Bool
        public var flipV: Bool
        public var cropX: Double?
        public var cropY: Double?
        public var cropWidth: Double?
        public var cropHeight: Double?
        public var speed: Double
        public var mute: Bool
        public var scaleWidth: Int?
        /// `none`, `medium` or `high`.
        public var compression: String
        /// `mp4`, `mov`, `mkv`, `webm` or `gif`.
        public var format: String

        /// The ADBKit options this describes.
        ///
        /// An unknown compression or format falls back to the default rather
        /// than failing the request: the alternative is a client that sends a
        /// newer value getting an error instead of an export.
        public var resolved: VideoExportOptions {
            var crop: CropRect?
            if let x = cropX, let y = cropY, let width = cropWidth, let height = cropHeight {
                crop = CropRect(x: x, y: y, width: width, height: height)
            }
            return VideoExportOptions(
                trimStart: trimStart,
                trimEnd: trimEnd,
                rotationDegrees: rotationDegrees,
                flipH: flipH,
                flipV: flipV,
                crop: crop,
                speed: speed,
                mute: mute,
                scaleWidth: scaleWidth,
                compression: CompressionLevel(rawValue: compression) ?? .none,
                format: VideoFormat(rawValue: format) ?? .mp4)
        }
    }

    public struct ExportRequest: Codable, Equatable, Sendable {
        public let path: String
        /// Where the result should land, chosen by the host's save dialog.
        public let destination: String
        public let options: ExportOptions
    }

    public struct ExportResponse: Codable, Equatable, Sendable {
        public let path: String
        public init(path: String) { self.path = path }
    }

    public struct RemoveRequest: Codable, Equatable, Sendable {
        public let path: String
        public init(path: String) { self.path = path }
    }

    public static let ffmpegMissing = DaemonProtocol.ErrorBody(
        code: "ffmpeg_missing",
        message: "ffmpeg is not installed. Download it from Settings ▸ Tools.")
}

enum VideoRoutes {
    static func formats() -> DaemonProtocol.Answer {
        (200, DaemonProtocol.encoded(VideoProtocol.FormatsResponse(
            extensions: VideoInputFormat.fileExtensions)))
    }

    static func proxy(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(VideoProtocol.ProxyRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let path = try await backend.videoProxy(of: request.path, mode: request.mode)
            return (200, DaemonProtocol.encoded(VideoProtocol.ProxyResponse(path: path)))
        } catch VideoBackendError.ffmpegMissing {
            return (503, DaemonProtocol.encoded(VideoProtocol.ffmpegMissing))
        } catch {
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "ffmpeg_failed", message: "Could not convert that video.",
                detail: "\(error)")))
        }
    }

    static func export(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(VideoProtocol.ExportRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        do {
            let path = try await backend.exportVideo(
                source: request.path, options: request.options.resolved,
                destination: request.destination)
            return (200, DaemonProtocol.encoded(VideoProtocol.ExportResponse(path: path)))
        } catch VideoBackendError.ffmpegMissing {
            return (503, DaemonProtocol.encoded(VideoProtocol.ffmpegMissing))
        } catch {
            // ffmpeg's own words: "the codec is not supported" says more than
            // "the export failed", and the tail is what `stderrTail` keeps.
            return (502, DaemonProtocol.encoded(DaemonProtocol.ErrorBody(
                code: "ffmpeg_failed", message: "The export failed.",
                detail: "\(error)")))
        }
    }

    /// Deletes a proxy once the editor is done with it. Best-effort: a proxy
    /// that has already gone is the outcome the caller wanted.
    static func removeProxy(body: Data, backend: any DaemonBackend) async -> DaemonProtocol.Answer {
        guard let request = try? JSONDecoder().decode(VideoProtocol.RemoveRequest.self, from: body)
        else { return (400, DaemonProtocol.encoded(DaemonProtocol.badRequest)) }
        await backend.removeVideoProxy(at: request.path)
        return (200, DaemonProtocol.encoded(ActionProtocol.RunResponse(
            FeatureResult(ok: true, message: "Removed"))))
    }
}

/// What the video backend can fail with, kept apart from ffmpeg's own failures
/// so a missing tool answers 503 with somewhere to go rather than 502 with a
/// process error nobody can act on.
enum VideoBackendError: Error, CustomStringConvertible {
    case ffmpegMissing
    case failed(String)

    var description: String {
        switch self {
        case .ffmpegMissing: return "ffmpeg is not installed"
        case .failed(let reason): return reason
        }
    }
}
