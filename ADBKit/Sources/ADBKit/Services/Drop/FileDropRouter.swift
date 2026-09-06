import Foundation

/// One path handed over by a drag, with the one fact about it that extension
/// matching can't answer.
public struct DroppedPath: Sendable, Equatable, Hashable {
    public let path: String
    public let isDirectory: Bool

    public init(path: String, isDirectory: Bool = false) {
        self.path = path
        self.isDirectory = isDirectory
    }

    /// The file name, for display and for the device-side destination.
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// What a dropped path is, decided by extension alone — the same rule the
/// open panels and the Finder document types use, so a drag and a double-click
/// can never disagree about a file.
public enum DroppedFileKind: Sendable, Equatable {
    /// An installable Android package (`.apk` and the three split containers).
    case appPackage(AppPackageFormat)
    /// An Android App Bundle. Not installable — it converts to an APK first.
    case appBundle
    /// A container the video editor opens.
    case video(VideoInputFormat)
    case folder
    case other
}

/// Where a drop goes when the surface under the cursor claims nothing for it.
///
/// The cases map one-to-one onto the App's existing Finder-open entry points,
/// which is the point: a double-clicked file and a dragged one resolve through
/// the same table instead of two hand-written filters that drift apart.
public enum DropRoute: Sendable, Equatable {
    case openPackages([String])
    case convertBundles([String])
    case openVideos([String])
    case copyToDevice([String])
    /// Nothing can be done with these — no device to copy them to.
    case unsupported([String])
}

/// What a drop onto a device surface (the mirror, a wall tile, a pop-out
/// window) will do. The surface owns one device, so there is no targeting
/// question to answer: everything here lands on that serial.
public struct DeviceDropPlan: Sendable, Equatable {
    /// Packages to install.
    public var installs: [String]
    /// App Bundles, which convert to an APK before they can be installed.
    public var bundles: [String]
    /// Files (and folders) to copy into `destination`.
    public var copies: [String]
    /// The device directory `copies` land in.
    public var destination: String

    public init(installs: [String] = [], bundles: [String] = [], copies: [String] = [], destination: String) {
        self.installs = installs
        self.bundles = bundles
        self.copies = copies
        self.destination = destination
    }

    public var isEmpty: Bool { installs.isEmpty && bundles.isEmpty && copies.isEmpty }

    /// Everything the plan touches, in the order it arrived.
    public var allPaths: [String] { installs + bundles + copies }

    /// True when the drop carries something that could plausibly be *stored*
    /// rather than installed — which is the only genuine ambiguity a drop on a
    /// mirror has, and so the only time the overlay offers a second zone.
    public var hasAlternative: Bool { !installs.isEmpty || !bundles.isEmpty }

    /// The same drop, with every package treated as a file to copy. What the
    /// overlay's secondary zone commits to.
    public var copyingEverything: DeviceDropPlan {
        DeviceDropPlan(copies: allPaths, destination: destination)
    }
}

/// What the drop overlay says while the drag is still in the air. Pure, so the
/// wording is tested rather than eyeballed — the whole design rests on the
/// reader believing this sentence before they let go.
public struct DropAnnouncement: Sendable, Equatable {
    /// SF Symbol name. ADBKit stays UI-free: this is a string, not an Image.
    public var symbol: String
    public var verb: String
    public var detail: String
    /// The secondary zone's label, when there is a second choice.
    public var alternative: String?
    /// True when the drop can't be honored — the overlay reads as a refusal
    /// rather than a promise.
    public var refusal: Bool

    public init(
        symbol: String, verb: String, detail: String,
        alternative: String? = nil, refusal: Bool = false
    ) {
        self.symbol = symbol
        self.verb = verb
        self.detail = detail
        self.alternative = alternative
        self.refusal = refusal
    }
}

/// The one table that decides what a dropped file does, wherever it lands.
public enum FileDropRouter {
    /// Where files copied to a device go. Deliberately one predictable folder
    /// rather than routing by type into Pictures/Movies/Music: the overlay
    /// names it before the drop, and a person hunting for what they just sent
    /// should only ever have one place to look. Matches scrcpy's default, so
    /// the habit transfers.
    public static let defaultDestination = "/sdcard/Download"

    public static func kind(of dropped: DroppedPath) -> DroppedFileKind {
        if dropped.isDirectory { return .folder }
        if let package = AppPackageFormat.detect(fileName: dropped.name) { return .appPackage(package) }
        let ext = URL(fileURLWithPath: dropped.name).pathExtension.lowercased()
        if ext == "aab" { return .appBundle }
        if let video = VideoInputFormat.detect(fileName: dropped.name) { return .video(video) }
        return .other
    }

    // MARK: - A drop on a device surface

    public static func plan(
        _ dropped: [DroppedPath], destination: String = defaultDestination
    ) -> DeviceDropPlan {
        var plan = DeviceDropPlan(destination: destination)
        for item in dropped {
            switch kind(of: item) {
            case .appPackage: plan.installs.append(item.path)
            case .appBundle: plan.bundles.append(item.path)
            // A video dropped on a phone is a file being sent to the phone.
            // Only a surface with nothing to do with it routes it to the editor.
            case .video, .folder, .other: plan.copies.append(item.path)
            }
        }
        return plan
    }

    // MARK: - A drop on a surface that claims nothing

    /// Group by kind and hand each group to the feature that owns it, so a
    /// drop is never silently swallowed. Order is fixed (packages, bundles,
    /// videos, files) so a mixed drop behaves the same way twice.
    public static func routes(
        for dropped: [DroppedPath], hasDevice: Bool, destination: String = defaultDestination
    ) -> [DropRoute] {
        var packages: [String] = []
        var bundles: [String] = []
        var videos: [String] = []
        var rest: [String] = []
        for item in dropped {
            switch kind(of: item) {
            case .appPackage: packages.append(item.path)
            case .appBundle: bundles.append(item.path)
            case .video: videos.append(item.path)
            case .folder, .other: rest.append(item.path)
            }
        }
        var routes: [DropRoute] = []
        if !packages.isEmpty { routes.append(.openPackages(packages)) }
        if !bundles.isEmpty { routes.append(.convertBundles(bundles)) }
        if !videos.isEmpty { routes.append(.openVideos(videos)) }
        if !rest.isEmpty { routes.append(hasDevice ? .copyToDevice(rest) : .unsupported(rest)) }
        return routes
    }

    // MARK: - Wording

    public static func announcement(
        for plan: DeviceDropPlan, deviceName: String, copyingInstead: Bool = false
    ) -> DropAnnouncement {
        let effective = copyingInstead ? plan.copyingEverything : plan
        if effective.isEmpty {
            return DropAnnouncement(
                symbol: "xmark.circle", verb: "Nothing to drop here",
                detail: "The drag carried no files.", refusal: true)
        }
        let alternative = (!copyingInstead && plan.hasAlternative)
            ? "…or copy to \(plan.destination)" : nil
        var verbs: [String] = []
        if !effective.installs.isEmpty { verbs.append(installVerb(effective.installs.count)) }
        if !effective.bundles.isEmpty { verbs.append(bundleVerb(effective.bundles.count)) }
        if !effective.copies.isEmpty { verbs.append(copyVerb(effective.copies.count)) }
        // "Copy to Pixel 7" but "Install on Pixel 7" — the preposition follows
        // the verb, and a mixed drop leads with the install. A bundle names no
        // device at all: converting happens on the Mac, and promising an
        // install "on Pixel 7" would overstate what the drop actually starts.
        let onlyCopies = effective.installs.isEmpty && effective.bundles.isEmpty
        let namesDevice = !effective.installs.isEmpty || !effective.copies.isEmpty
        let suffix = namesDevice ? " \(onlyCopies ? "to" : "on") \(deviceName)" : ""
        return DropAnnouncement(
            symbol: onlyCopies ? "arrow.down.doc" : "arrow.down.app",
            verb: verbs.joined(separator: " · ") + suffix,
            detail: detail(for: effective),
            alternative: alternative)
    }

    public static func announcement(for routes: [DropRoute]) -> DropAnnouncement? {
        guard !routes.isEmpty else { return nil }
        if routes.count == 1, case let .unsupported(paths) = routes[0] {
            return DropAnnouncement(
                symbol: "xmark.circle",
                verb: paths.count == 1
                    ? "Droidective can't open \(name(paths[0]))"
                    : "Droidective can't open these \(paths.count) files",
                detail: "Connect a device to copy files instead.",
                refusal: true)
        }
        let verbs = routes.map(verb(for:))
        let counted = routes.reduce(0) { $0 + count(of: $1) }
        return DropAnnouncement(
            symbol: "arrow.down.forward.square",
            verb: verbs.joined(separator: " · "),
            detail: counted == 1 ? name(firstPath(of: routes[0])) : "\(counted) files")
    }

    // MARK: - Private wording helpers

    private static func installVerb(_ count: Int) -> String {
        count == 1 ? "Install" : "Install \(count) apps"
    }

    private static func bundleVerb(_ count: Int) -> String {
        count == 1 ? "Convert to APK" : "Convert \(count) bundles to APKs"
    }

    private static func copyVerb(_ count: Int) -> String {
        count == 1 ? "Copy" : "Copy \(count) files"
    }

    private static func detail(for plan: DeviceDropPlan) -> String {
        let total = plan.allPaths.count
        if total == 1, plan.copies.isEmpty { return name(plan.allPaths[0]) }
        if plan.copies.isEmpty { return "\(total) packages" }
        if total == 1 { return "\(name(plan.copies[0])) → \(plan.destination)" }
        return "\(plan.copies.count) to \(plan.destination)"
    }

    private static func verb(for route: DropRoute) -> String {
        switch route {
        case let .openPackages(paths):
            paths.count == 1 ? "Open app package" : "Open \(paths.count) app packages"
        case .convertBundles:
            "Convert to APK"
        case let .openVideos(paths):
            paths.count == 1 ? "Open in Video Editor" : "Open \(paths.count) videos"
        case let .copyToDevice(paths):
            paths.count == 1 ? "Copy to device" : "Copy \(paths.count) files to device"
        case let .unsupported(paths):
            paths.count == 1 ? "Can't open this file" : "Can't open these \(paths.count) files"
        }
    }

    private static func count(of route: DropRoute) -> Int { paths(of: route).count }

    private static func firstPath(of route: DropRoute) -> String { paths(of: route).first ?? "" }

    private static func paths(of route: DropRoute) -> [String] {
        switch route {
        case let .openPackages(paths), let .convertBundles(paths),
             let .openVideos(paths), let .copyToDevice(paths), let .unsupported(paths):
            paths
        }
    }

    private static func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
}
