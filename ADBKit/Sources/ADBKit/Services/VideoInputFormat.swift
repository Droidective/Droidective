import Foundation

/// Every container the video editor opens — the single source of truth for the
/// open panel's filter, the drop filter, and the Finder document types, the way
/// `AppPackageFormat` is for installable packages. A format added here widens
/// every entry point at once.
///
/// This is the *input* list and is deliberately separate from `VideoFormat`,
/// which enumerates export targets: the two overlap (mp4/mov/mkv/webm) but
/// neither contains the other — GIF is an output only, and avi/flv/ts/wmv are
/// inputs only, because ffmpeg reads far more than the editor should offer to
/// write.
///
/// Membership means "ffmpeg demuxes this reliably", not "AVFoundation plays
/// it" — most of this list AVFoundation refuses. Playback is handled by
/// probing the file and building a proxy when it can't be played
/// (`VideoEditService.playableProxy`), so the list needs no
/// `isAVFoundationNative` flag and would be wrong to carry one: an `.mp4`
/// holding AV1 fails the same probe an `.mkv` does.
public enum VideoInputFormat: String, Sendable, CaseIterable {
    /// The recorder's own container, and the export default.
    case mp4
    case mov
    case m4v
    /// Matroska and WebM — what a Chrome or OBS capture usually is. Neither
    /// conforms to `public.movie`, so both need declared types to be openable.
    case mkv
    case webm
    case avi
    case flv
    /// MPEG transport streams, as produced by screen capture boxes and HLS
    /// segment dumps.
    case ts
    case m2ts
    case mpg
    case mpeg
    case wmv
    case threeGP = "3gp"
    case ogv
    /// Animated GIF, which is also an export target — trimming and cropping
    /// one is the same operation as for any other input.
    case gif

    /// Every extension the editor opens, lowercased.
    public static var fileExtensions: [String] { allCases.map(\.rawValue) }

    /// The format of `fileName`, or nil when the extension isn't one we open.
    /// Case-insensitive by construction — a camera writes `.MOV`, a transport
    /// stream dump `.TS`.
    public static func detect(fileName: String) -> VideoInputFormat? {
        VideoInputFormat(rawValue: URL(fileURLWithPath: fileName).pathExtension.lowercased())
    }

    public var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "QuickTime"
        case .m4v: return "M4V"
        case .mkv: return "Matroska"
        case .webm: return "WebM"
        case .avi: return "AVI"
        case .flv: return "Flash Video"
        case .ts: return "MPEG Transport Stream"
        case .m2ts: return "AVCHD"
        case .mpg, .mpeg: return "MPEG"
        case .wmv: return "Windows Media"
        case .threeGP: return "3GP"
        case .ogv: return "Ogg Video"
        case .gif: return "GIF"
        }
    }
}
