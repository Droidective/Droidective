import Foundation

/// Android's marketing names for its API levels, for the places that show an
/// app's SDK requirements: "API 24" means little to most people, "Android 7.0"
/// does. Levels past the table read as the bare level rather than a guess.
public enum AndroidRelease {
    static let names: [Int: String] = [
        16: "4.1", 17: "4.2", 18: "4.3", 19: "4.4", 20: "4.4W",
        21: "5.0", 22: "5.1", 23: "6.0", 24: "7.0", 25: "7.1",
        26: "8.0", 27: "8.1", 28: "9", 29: "10", 30: "11",
        31: "12", 32: "12L", 33: "13", 34: "14", 35: "15", 36: "16", 37: "17",
    ]

    /// "Android 15 (API 35)", "API 40" past the table, and the raw value for a
    /// preview SDK's codename (`targetSdkVersion:'Baklava'`). A minor SDK
    /// level (`36.1`, from Android 16 on) is named by its major.
    public static func describe(apiLevel: String) -> String {
        guard let major = apiLevel.split(separator: ".").first.flatMap({ Int($0) }) else { return apiLevel }
        guard let name = names[major] else { return "API \(apiLevel)" }
        return "Android \(name) (API \(apiLevel))"
    }
}
