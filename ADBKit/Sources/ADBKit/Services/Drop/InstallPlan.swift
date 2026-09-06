import Foundation

/// The version of a package as the *device* reports it, narrowed to the two
/// fields the install prompt compares. `AppInfo` carries em-dashes for "not
/// known", which is why both are optional here rather than defaulted strings.
public struct InstalledAppVersion: Sendable, Equatable {
    public var versionName: String?
    public var versionCode: String?

    public init(versionName: String? = nil, versionCode: String? = nil) {
        self.versionName = InstalledAppVersion.cleaned(versionName)
        self.versionCode = InstalledAppVersion.cleaned(versionCode)
    }

    /// `AppInfo.notInstalled` fills its fields with "—"; dumpsys can also
    /// report "null". Neither is a version.
    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "—" || trimmed == "-" || trimmed == "null" { return nil }
        return trimmed
    }
}

/// How the dropped package relates to what is already on the device. This is
/// the sentence the whole install sheet is built on, so it is decided once,
/// here, and tested — not inferred in a view.
public enum InstallRelation: String, Sendable, Equatable, CaseIterable {
    case notInstalled
    case reinstall
    case update
    case downgrade
    /// The app is there but the two versions can't be compared — no aapt2 to
    /// read the APK, or a version code the device didn't report.
    case unknown
}

/// What the install prompt offers, and what it must refuse.
public struct InstallDecision: Sendable, Equatable {
    public var relation: InstallRelation
    /// The primary button's label — it names what will actually happen.
    public var primaryTitle: String
    /// Whether "keep app data" (a plain `adb install -r`) is on the table.
    public var canKeepData: Bool
    /// Why it isn't, when it isn't.
    public var keepDataNote: String?
    /// Whether the sheet should preselect Replace (uninstall, then install).
    public var replaceByDefault: Bool
    /// Whether the sheet has a choice to make at all. A first install doesn't.
    public var offersChoice: Bool

    public init(
        relation: InstallRelation, primaryTitle: String, canKeepData: Bool,
        keepDataNote: String?, replaceByDefault: Bool, offersChoice: Bool
    ) {
        self.relation = relation
        self.primaryTitle = primaryTitle
        self.canKeepData = canKeepData
        self.keepDataNote = keepDataNote
        self.replaceByDefault = replaceByDefault
        self.offersChoice = offersChoice
    }
}

public enum InstallPlan {
    /// Compare two Android `versionCode`s.
    ///
    /// The code is the authoritative integer and the *name* is only a label —
    /// "3.0" against "3.0.1" is a string, not an ordering. Returns nil when
    /// either side is missing or isn't a plain integer, which is the honest
    /// answer: the sheet then says it can't tell rather than guessing.
    public static func compareVersionCodes(_ local: String?, _ installed: String?) -> ComparisonResult? {
        guard let left = integerCode(local), let right = integerCode(installed) else { return nil }
        if left == right { return .orderedSame }
        return left > right ? .orderedDescending : .orderedAscending
    }

    private static func integerCode(_ value: String?) -> UInt64? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCII), trimmed.allSatisfy(\.isNumber) else { return nil }
        return UInt64(trimmed)
    }

    /// The decision for one package against one device.
    ///
    /// A downgrade is the case worth getting right: Android refuses
    /// `INSTALL_FAILED_VERSION_DOWNGRADE` for an in-place reinstall, so the
    /// only route is uninstall-then-install — which wipes app data. Saying
    /// that up front beats discovering it from a failure.
    public static func decide(local: ApkInfo, installed: InstalledAppVersion?) -> InstallDecision {
        guard let installed, installed.versionName != nil || installed.versionCode != nil else {
            return InstallDecision(
                relation: .notInstalled, primaryTitle: "Install", canKeepData: true,
                keepDataNote: nil, replaceByDefault: false, offersChoice: false)
        }
        switch compareVersionCodes(local.versionCode, installed.versionCode) {
        case .orderedDescending:
            return InstallDecision(
                relation: .update, primaryTitle: "Update", canKeepData: true,
                keepDataNote: nil, replaceByDefault: false, offersChoice: true)
        case .orderedSame:
            return InstallDecision(
                relation: .reinstall, primaryTitle: "Reinstall", canKeepData: true,
                keepDataNote: nil, replaceByDefault: false, offersChoice: true)
        case .orderedAscending:
            return InstallDecision(
                relation: .downgrade, primaryTitle: "Downgrade & Replace", canKeepData: false,
                keepDataNote: "Not possible for a downgrade", replaceByDefault: true,
                offersChoice: true)
        case nil:
            return InstallDecision(
                relation: .unknown, primaryTitle: "Install", canKeepData: true,
                keepDataNote: local.versionCode == nil
                    ? "Version details need the Android SDK build-tools" : nil,
                replaceByDefault: false, offersChoice: true)
        }
    }

    /// A one-line version for the sheet's comparison rows: "3.0.2  (30201)",
    /// or just one half when the other is missing.
    public static func versionLabel(name: String?, code: String?) -> String {
        switch (name, code) {
        case let (name?, code?): "\(name)  (\(code))"
        case let (name?, nil): name
        case let (nil, code?): "(\(code))"
        case (nil, nil): "Unknown"
        }
    }

    /// True when an install failure is the kind an uninstall-first retry
    /// actually fixes — the recovery the failure chip offers. Anything else
    /// (no storage, wrong ABI, a corrupt APK) is not helped by wiping the app,
    /// so it must not be offered.
    ///
    /// Recognises adb's own `INSTALL_FAILED_*` codes *and* the wording
    /// `AppInstallService.friendlyReason` replaces them with, because by the
    /// time a failure reaches the UI it may be either: the raw output is kept
    /// on the job, the friendly one-liner is what the chip shows, and a caller
    /// reading the wrong one would silently never offer the recovery.
    /// `theFriendlyWordingOfARecoverableCodeIsAlsoRecognised` pins the pair.
    public static func isResolvedByReplacing(_ failure: String) -> Bool {
        let recoverable = [
            "INSTALL_FAILED_UPDATE_INCOMPATIBLE",
            "INSTALL_FAILED_VERSION_DOWNGRADE",
            "INSTALL_FAILED_DUPLICATE_PERMISSION",
            "INSTALL_FAILED_ALREADY_EXISTS",
            "signatures do not match",
            // The friendly halves of the same four.
            "uninstall it first",
            "already installed",
        ]
        return recoverable.contains { failure.localizedCaseInsensitiveContains($0) }
    }
}
