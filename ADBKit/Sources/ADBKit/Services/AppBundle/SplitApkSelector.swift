import Foundation

/// What a device can run, as far as split selection cares. Built from `getprop`
/// so the whole selection stays a pure function over values.
public struct DeviceSpec: Sendable, Equatable {
    /// Supported ABIs, best first (`ro.product.cpu.abilist` order).
    public var abis: [String]
    /// Screen density in dpi (`ro.sf.lcd_density`); 0 when unknown.
    public var densityDpi: Int
    /// Device languages as ISO codes, e.g. `["en"]`.
    public var languages: [String]

    public init(abis: [String], densityDpi: Int, languages: [String]) {
        self.abis = abis
        self.densityDpi = densityDpi
        self.languages = languages
    }

    /// Read the spec out of a `getprop` dump. `abilist` is the modern property;
    /// `ro.product.cpu.abi`(+`abi2`) is the fallback for old devices. Density
    /// falls back to `ro.sf.lcd_density_density`, then the vendor override.
    /// Locales arrive as `en-US` / `en_US` and are reduced to the language.
    public static func parse(props: [String: String]) -> DeviceSpec {
        var abis = splitList(props["ro.product.cpu.abilist"])
        if abis.isEmpty {
            abis = [props["ro.product.cpu.abi"], props["ro.product.cpu.abi2"]]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let densityKeys = ["ro.sf.lcd_density", "ro.sf.lcd_density_density", "qemu.sf.lcd_density"]
        let density = densityKeys.lazy.compactMap { props[$0].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }.first ?? 0

        let localeKeys = ["persist.sys.locale", "ro.product.locale", "ro.product.locale.language"]
        let languages = localeKeys
            .compactMap { props[$0] }
            .flatMap { splitList($0) }
            .compactMap { language(from: $0) }
            .reduced()
        return DeviceSpec(abis: abis, densityDpi: density, languages: languages)
    }

    /// The leading language subtag of a locale, lowercased (`pt-BR` → `pt`).
    private static func language(from locale: String) -> String? {
        let tag = locale
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "-")
            .first?
            .lowercased() ?? ""
        return tag.count >= 2 ? tag : nil
    }

    private static func splitList(_ value: String?) -> [String] {
        (value ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Which splits of a bundle to install on a given device, and what that choice
/// implies for the caller (an unmatched ABI is a hard failure worth reporting
/// before adb does).
public struct SplitSelection: Sendable, Equatable {
    /// The chosen files, in the order they were given.
    public var files: [String]
    /// The ABI whose splits were kept, if the bundle has per-ABI splits.
    public var chosenABI: String?
    /// The bundle ships ABI splits but none match this device — installing the
    /// rest would produce an app that crashes on its first native call.
    public var abiUnmatched: Bool

    public init(files: [String], chosenABI: String?, abiUnmatched: Bool) {
        self.files = files
        self.chosenABI = chosenABI
        self.abiUnmatched = abiUnmatched
    }
}

/// Picks the subset of a split bundle's APKs that belongs on one device.
///
/// A split app is a base APK plus config splits qualified by ABI, screen
/// density, or language. Installing *all* of them wastes transfer time and can
/// leave the wrong native library in place, so the selection mirrors what Play
/// would deliver: the base and every feature module, one ABI, one density, and
/// the device's languages.
public enum SplitApkSelector {
    /// The qualifier a split's file name encodes.
    enum Qualifier: Equatable {
        /// A base APK or a feature module — always installed.
        case base
        case abi(String)
        case density(String)
        case language(String)
        /// A qualifier we don't model (texture compression, device tier). Kept,
        /// because dropping a split the app needs fails worse than carrying one
        /// it doesn't.
        case other(String)
    }

    static let knownABIs: Set<String> = [
        "armeabi", "armeabi_v7a", "arm64_v8a", "x86", "x86_64", "mips", "mips64", "riscv64",
    ]

    /// Android's density buckets in dpi. `nodpi`/`anydpi` are density-agnostic
    /// and always kept.
    static let densityBuckets: [String: Int] = [
        "ldpi": 120, "mdpi": 160, "tvdpi": 213, "hdpi": 240,
        "xhdpi": 320, "xxhdpi": 480, "xxxhdpi": 640,
    ]
    static let densityAgnostic: Set<String> = ["nodpi", "anydpi"]

    /// Classify one split by file name. Two naming conventions are in the wild:
    /// Play/APKPure/APKMirror's `config.<qualifier>.apk` (optionally prefixed by
    /// a module, e.g. `myfeature.config.xxhdpi.apk`) and bundletool's
    /// `base-<qualifier>.apk` / `base-master.apk`.
    static func qualifier(ofFile fileName: String) -> Qualifier {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.lowercased()
        let token: String
        if let configRange = stem.range(of: "config.", options: .backwards) {
            token = String(stem[configRange.upperBound...])
        } else if let dash = stem.lastIndex(of: "-") {
            token = String(stem[stem.index(after: dash)...])
        } else {
            return .base
        }
        // bundletool names the base split of each module `<module>-master`.
        guard !token.isEmpty, token != "master" else { return .base }
        return classify(token)
    }

    /// Map a qualifier token to its dimension. ABI and density names are closed
    /// sets, so they're checked first; a language tag is the only other thing
    /// Play emits that looks like a bare word.
    static func classify(_ token: String) -> Qualifier {
        let normalized = token.replacingOccurrences(of: "-", with: "_")
        if knownABIs.contains(normalized) { return .abi(normalized) }
        if densityBuckets[normalized] != nil || densityAgnostic.contains(normalized) { return .density(normalized) }
        // Texture-compression splits (`tcf_astc`, `tcf_etc2`) would otherwise
        // read as the language `tcf` and be dropped on every non-`tcf` device.
        if normalized.hasPrefix("tcf_") { return .other(normalized) }
        if isLanguageTag(normalized) { return .language(String(normalized.prefix(while: { $0 != "_" }))) }
        return .other(normalized)
    }

    /// A language qualifier is a 2–3 letter ISO code, optionally followed by a
    /// script/region subtag (`pt_br`, `b+sr+latn`).
    private static func isLanguageTag(_ token: String) -> Bool {
        let head = token.prefix(while: { $0.isLetter && $0.isASCII })
        guard (2...3).contains(head.count) else { return false }
        let rest = token.dropFirst(head.count)
        return rest.isEmpty || rest.first == "_" || rest.first == "+"
    }

    /// Choose the splits to install. `files` may be paths; only the last path
    /// component is inspected, and the originals are returned untouched.
    ///
    /// Rules: every base/feature APK is kept; ABI splits collapse to the best
    /// ABI the device reports; density splits collapse to the bucket nearest the
    /// device (preferring one at or above it, so nothing is upscaled); language
    /// splits keep the device's languages plus English, which is the near
    /// universal fallback when a device's language isn't shipped.
    public static func select(files: [String], spec: DeviceSpec) -> SplitSelection {
        let classified = files.map { (file: $0, qualifier: qualifier(ofFile: $0)) }

        let availableABIs = Set(classified.compactMap { if case .abi(let value) = $0.qualifier { value } else { nil } })
        let chosenABI = spec.abis
            .map { $0.replacingOccurrences(of: "-", with: "_").lowercased() }
            .first { availableABIs.contains($0) }
        let chosenDensity = pickDensity(from: classified, deviceDpi: spec.densityDpi)
        let wantedLanguages = Set(spec.languages.map { $0.lowercased() }).union(["en"])

        let kept = classified.filter { entry in
            switch entry.qualifier {
            case .base, .other: true
            case .abi(let value): value == chosenABI
            case .density(let value): densityAgnostic.contains(value) || value == chosenDensity
            case .language(let value): wantedLanguages.contains(value)
            }
        }
        return SplitSelection(
            files: kept.map(\.file),
            chosenABI: chosenABI,
            abiUnmatched: !availableABIs.isEmpty && chosenABI == nil)
    }

    /// The density bucket to keep: the smallest one at or above the device's
    /// dpi, else the largest below it. With an unknown device density (0) the
    /// largest bucket wins — over-sized art downscales cleanly, the reverse
    /// looks blurry.
    private static func pickDensity(
        from classified: [(file: String, qualifier: Qualifier)], deviceDpi: Int
    ) -> String? {
        let buckets = classified
            .compactMap { entry -> (name: String, dpi: Int)? in
                guard case .density(let name) = entry.qualifier, let dpi = densityBuckets[name] else { return nil }
                return (name, dpi)
            }
            .reduced { $0.name == $1.name }
        guard !buckets.isEmpty else { return nil }
        let largest = buckets.max { $0.dpi < $1.dpi }
        guard deviceDpi > 0 else { return largest?.name }
        let atOrAbove = buckets.filter { $0.dpi >= deviceDpi }.min { $0.dpi < $1.dpi }
        return (atOrAbove ?? largest)?.name
    }
}

extension Array {
    /// Order-preserving de-duplication.
    fileprivate func reduced(_ areEqual: (Element, Element) -> Bool) -> [Element] {
        var seen: [Element] = []
        for element in self where !seen.contains(where: { areEqual($0, element) }) {
            seen.append(element)
        }
        return seen
    }
}

extension Array where Element: Hashable {
    fileprivate func reduced() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
