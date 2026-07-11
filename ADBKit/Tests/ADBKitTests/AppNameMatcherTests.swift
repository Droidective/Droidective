import Testing
@testable import ADBKit

@Suite struct AppNameMatcherTests {
    private let installed = [
        "com.acme.myapp",
        "com.foodhub.driver.dev",
        "com.example.shop",
        "org.another.shop",
    ]

    @Test func matchesExactLastSegmentIgnoringCaseAndSpaces() {
        #expect(AppNameMatcher.match(appName: "My App", in: installed) == "com.acme.myapp")
        #expect(AppNameMatcher.match(appName: "MYAPP", in: installed) == "com.acme.myapp")
    }

    @Test func fallsBackToUniqueSubstringMatchForVariantSuffixes() {
        // Dev builds carry a variant suffix, so the last segment ("dev")
        // never equals the app name — the substring pass must find it.
        #expect(AppNameMatcher.match(appName: "FoodHub Driver", in: installed) == "com.foodhub.driver.dev")
    }

    @Test func ambiguousMatchesReturnNilInsteadOfGuessing() {
        // Two packages end in "shop" — restarting the wrong app is worse
        // than asking, so ambiguity must not resolve arbitrarily.
        #expect(AppNameMatcher.match(appName: "Shop", in: installed) == nil)
    }

    @Test func noMatchAndEmptyInputsReturnNil() {
        #expect(AppNameMatcher.match(appName: "Untracked", in: installed) == nil)
        #expect(AppNameMatcher.match(appName: "", in: installed) == nil)
        #expect(AppNameMatcher.match(appName: "My App", in: []) == nil)
        #expect(AppNameMatcher.match(appName: "…", in: installed) == nil)
    }
}
