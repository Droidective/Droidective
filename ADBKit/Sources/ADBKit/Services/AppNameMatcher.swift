import Foundation

/// Matches a human app display name (what a Reactotron client or Metro target
/// reports about itself, e.g. "Food Hub") against installed package ids, so
/// the restart flows can auto-detect which app to restart. Pure and
/// conservative: a match is returned only when it's unambiguous.
public enum AppNameMatcher {
    /// The single package matching `appName`, or nil when none or several do.
    /// An exact match on the package's last segment wins ("My App" →
    /// `com.acme.myapp`); otherwise the name appearing anywhere in the package
    /// id is accepted if exactly one package qualifies ("Food Hub" →
    /// `com.foodhub.driver.dev`).
    public static func match(appName: String, in packages: [String]) -> String? {
        let name = normalize(appName)
        guard !name.isEmpty else { return nil }
        let lastSegment = packages.filter {
            normalize(String($0.split(separator: ".").last ?? "")) == name
        }
        if lastSegment.count == 1 { return lastSegment[0] }
        if lastSegment.count > 1 { return nil }
        let containing = packages.filter { normalize($0).contains(name) }
        return containing.count == 1 ? containing[0] : nil
    }

    /// Lowercased alphanumerics only, so "Food Hub" and `foodhub` compare equal.
    private static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })
    }
}
