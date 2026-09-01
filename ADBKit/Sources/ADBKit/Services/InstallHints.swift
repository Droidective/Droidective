import Foundation

/// Where to get a missing tool, worded for the machine that is missing it.
///
/// The app never installs a tool itself, on any platform, so the hint *is* the
/// whole answer — which makes a wrong one worse than none. "Install it via
/// Android Studio" is the right sentence on a Mac and a poor one on Ubuntu,
/// where the answer is a single apt command somebody can paste.
///
/// Pure and static so the wording is tested rather than eyeballed: the Doctor
/// and the device bar both read it, and neither can tell a good hint from a
/// stale one.
public enum InstallHints {
    /// The families whose package managers differ enough to change the answer.
    public enum LinuxFamily: String, Sendable, CaseIterable {
        case debian
        case fedora
        case arch
        case suse
        /// A distribution this build has no command for — name the package
        /// instead of guessing a package manager.
        case unknown
    }

    /// The family named by an `/etc/os-release` file.
    ///
    /// `ID_LIKE` is consulted after `ID` and matters more than it looks: Mint,
    /// Pop!_OS, Zorin and elementary all report their own `ID` and lean on
    /// `ID_LIKE=ubuntu debian`, and every one of them installs adb with apt.
    public static func linuxFamily(osRelease: String) -> LinuxFamily {
        let fields = parseOSRelease(osRelease)
        if let id = fields["ID"], let family = family(matching: [id]) { return family }
        if let like = fields["ID_LIKE"] {
            let tokens = like.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            if let family = family(matching: tokens) { return family }
        }
        return .unknown
    }

    private static func family(matching tokens: [String]) -> LinuxFamily? {
        for token in tokens {
            switch token.lowercased() {
            case "debian", "ubuntu", "raspbian", "linuxmint", "pop", "elementary", "zorin":
                return .debian
            case "fedora", "rhel", "centos", "rocky", "almalinux":
                return .fedora
            case "arch", "archlinux", "manjaro", "endeavouros":
                return .arch
            case "suse", "opensuse", "opensuse-tumbleweed", "opensuse-leap", "sles":
                return .suse
            default:
                continue
            }
        }
        return nil
    }

    /// `KEY=value` and `KEY="value"` lines, comments and blanks skipped.
    ///
    /// Split on `.newlines` rather than `"\n"`, as everything in this package
    /// does — the file is written by a package manager and has been seen with
    /// CRLF in container images.
    static func parseOSRelease(_ contents: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: "=")
            else { continue }
            let key = String(trimmed[trimmed.startIndex..<separator])
            var value = String(trimmed[trimmed.index(after: separator)...])
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            fields[key] = value
        }
        return fields
    }

    /// The one command that installs adb on this Linux family, or nil when the
    /// distribution is unknown and a guessed command would be worse than none.
    public static func adbCommand(for family: LinuxFamily) -> String? {
        switch family {
        case .debian: return "sudo apt install android-tools-adb"
        case .fedora: return "sudo dnf install android-tools"
        case .arch: return "sudo pacman -S android-tools"
        case .suse: return "sudo zypper install android-tools"
        case .unknown: return nil
        }
    }

    /// The adb hint for this machine.
    ///
    /// `osRelease` is passed in rather than read here so the wording stays
    /// testable for every distribution without one of them being installed.
    public static func adb(osRelease: String? = nil) -> String {
        #if os(Linux)
        let family = linuxFamily(osRelease: osRelease ?? "")
        if let command = adbCommand(for: family) {
            return "adb is missing. Install it with `\(command)`, then re-check."
        }
        return "adb is missing. Install your distribution's Android platform-tools "
            + "package (often called android-tools or android-tools-adb), then re-check."
        #elseif os(Windows)
        return "adb is missing. Install it with `winget install Google.PlatformTools`, "
            + "or unzip developer.android.com/tools/releases/platform-tools and add it "
            + "to PATH, then re-check."
        #else
        return "Install Android platform-tools — via Android Studio, or from "
            + "developer.android.com/tools/releases/platform-tools — then re-check."
        #endif
    }

    /// Read `/etc/os-release` if this machine has one. Nil everywhere else.
    public static func hostOSRelease() -> String? {
        #if os(Linux)
        return try? String(contentsOfFile: "/etc/os-release", encoding: .utf8)
        #else
        return nil
        #endif
    }
}
