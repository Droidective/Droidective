import { describe, expect, it } from "vitest"
import { matchAppName } from "@/lib/app-name-match"

/**
 * The same cases as ADBKit's `AppNameMatcherTests`, because both apps have to
 * make the same call from the same client name — and getting it wrong means
 * clearing the data of an app nobody asked about.
 */
const installed = [
  "com.acme.myapp",
  "com.foodhub.driver.dev",
  "com.example.shop",
  "org.another.shop",
]

describe("matchAppName", () => {
  it("matches an exact last segment, ignoring case and spaces", () => {
    expect(matchAppName("My App", installed)).toBe("com.acme.myapp")
    expect(matchAppName("MYAPP", installed)).toBe("com.acme.myapp")
  })

  it("falls back to a unique substring match for a variant suffix", () => {
    // A dev build carries a variant suffix, so its last segment ("dev") never
    // equals the app name — the substring pass has to find it.
    expect(matchAppName("FoodHub Driver", installed)).toBe("com.foodhub.driver.dev")
  })

  it("returns nothing rather than guessing between two candidates", () => {
    // Two packages end in "shop". Restarting the wrong app is worse than
    // asking, so ambiguity must not resolve arbitrarily.
    expect(matchAppName("Shop", installed)).toBeNull()
  })

  it("returns nothing for no match, or for nothing to match on", () => {
    expect(matchAppName("Untracked", installed)).toBeNull()
    expect(matchAppName("", installed)).toBeNull()
    expect(matchAppName("My App", [])).toBeNull()
    // Punctuation normalizes to an empty name, which must not match everything.
    expect(matchAppName("…", installed)).toBeNull()
  })

  it("prefers the exact last segment over a substring that also fits", () => {
    // `com.acme.myapp` and `com.other.myapp.helper` both contain "myapp"; only
    // one *ends* in it, and that is the answer rather than an ambiguity.
    expect(matchAppName("myapp", [...installed, "com.other.myapp.helper"])).toBe("com.acme.myapp")
  })
})
