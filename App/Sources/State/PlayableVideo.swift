import ADBKit
import UniformTypeIdentifiers

/// The App-layer view of `VideoInputFormat`, which is ADBKit's single source
/// of truth for the containers the video editor opens — a format added there
/// widens the open panel, the drop filter and the Finder router at once. The
/// mirror of `InstallablePackage`, and separate for the same reason:
/// `UniformTypeIdentifiers` is Apple-only and ADBKit stays portable.
enum PlayableVideo {
    /// The types the open panel offers. Derived from the extensions rather
    /// than a hand-written list of system UTTypes, which is what the panel
    /// used to carry: `.movie`/`.video` are AVFoundation's idea of a video,
    /// so `.mkv` and `.webm` were greyed out even though ffmpeg reads both.
    ///
    /// The extensions resolve to declared types because `project.yml`
    /// declares the ones macOS lacks (`UTImportedTypeDeclarations`) — without
    /// that, `UTType(filenameExtension:)` returns nil for `.mkv` and the
    /// format silently drops out of the panel.
    static var contentTypes: [UTType] {
        VideoInputFormat.fileExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func filter(_ urls: [URL]) -> [URL] {
        urls.filter { VideoInputFormat.detect(fileName: $0.lastPathComponent) != nil }
    }
}
