import Foundation

/// The last gate before anything leaves the machine.
///
/// The app promises — in Settings ▸ Privacy, in the privacy policy, and in the
/// doc comment on every sink — that no paths, URLs, device serials, package
/// ids, or command contents are ever sent. Until now that promise was a
/// property of the *call sites*: `track` takes `[String: Any]`, so any one of
/// them could pass a user's file path and nothing would notice. That is the
/// same shape of hazard as a missing `shellQuote`, and it has already been
/// paid for once — Sentry's `enableCaptureFailedRequests` was capturing the
/// URLs of servers users typed into API Testing, and it was caught by reading
/// the SDK's defaults rather than by anything in this code.
///
/// So the promise moves into the pipe. Every property crossing either sink is
/// scrubbed, and anything that does not look like a feature id, a version, a
/// count, or a fixed label is replaced with `redactedMarker` rather than
/// dropped — a redaction that leaves a visible hole is a bug report; a
/// silently missing key is a mystery.
///
/// What this can and cannot do, stated plainly, because a filter that is
/// trusted for more than it does is worse than none:
///
/// - It **catches** absolute and relative paths, home-relative paths, URLs of
///   any scheme, email addresses, IPv4 and IPv6 literals, query strings, shell
///   fragments, percent-encoding, quoted text, anything non-ASCII, anything
///   containing whitespace (which is what catches a command line), and
///   anything long enough to be prose.
/// - It **catches** reverse-DNS shapes, which is what an Android package id
///   looks like (`com.example.app`) — distinguished from a version string by
///   its components being non-numeric.
/// - It **cannot** catch a value that is genuinely shaped like a label. An
///   adb serial (`emulator-5554`) or a bare hostname is indistinguishable from
///   a feature id by shape alone. Those stay a call-site rule.
public enum TelemetryScrub {
    /// What a rejected value becomes. Deliberately visible: a hole in a
    /// dashboard is a question someone asks, and the answer is always a call
    /// site that needs fixing.
    public static let redactedMarker = "<redacted>"

    /// Longest string that can be a label rather than content. The longest
    /// legitimate value is `open_features`, a comma-joined list of every
    /// mounted feature id — around 220 characters with eighteen tabs open, so
    /// this is generous without admitting a paragraph.
    static let maximumLength = 512

    /// Characters a label may contain. No `/` or `\` (paths), no `:` (URLs,
    /// IPv6, `host:port`), no `@` (emails, user@host), no `~` (home), no `?`
    /// or `=` (query strings), no `%` (percent-encoding), no quotes, and
    /// nothing outside ASCII.
    ///
    /// **No whitespace either**, which is the rule that earns its keep: an
    /// adb command line (`adb shell pm clear com.foo`) clears every other test
    /// here — its words are alphanumeric, its package id is only two
    /// components — and command contents are precisely what the promise
    /// forbids. Nothing legitimate has a space in it: feature ids are kebab,
    /// `open_features` is comma-joined, versions are dotted. A value that
    /// wants a space is a sentence, and a sentence is content.
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._,+-")

    /// Whether a string may leave the machine as-is.
    public static func isSafe(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        guard value.allSatisfy({ allowed.contains($0) }) else { return false }
        guard !looksLikeIPv4(value) else { return false }
        guard !looksLikeReverseDNS(value) else { return false }
        return true
    }

    /// Scrub one property bag. Returns the cleaned bag and how many values
    /// were replaced, so the count itself can ride out as telemetry — a
    /// redaction counter that starts climbing is how a newly-leaking call site
    /// announces itself.
    public static func scrub(_ properties: [String: Any]) -> (properties: [String: Any], redacted: Int) {
        var cleaned: [String: Any] = [:]
        var redacted = 0
        for (key, value) in properties {
            // A key is written by a developer, never derived from user input,
            // but it crosses the same wire — hold it to the same shape so a
            // future `properties[userTypedName]` cannot slip through.
            let safeKey = isSafe(key) ? key : redactedMarker
            switch value {
            case let string as String:
                if isSafe(string) {
                    cleaned[safeKey] = string
                } else {
                    cleaned[safeKey] = redactedMarker
                    redacted += 1
                }
            case let strings as [String]:
                var list: [String] = []
                for element in strings {
                    if isSafe(element) {
                        list.append(element)
                    } else {
                        list.append(redactedMarker)
                        redacted += 1
                    }
                }
                cleaned[safeKey] = list
            case is Int, is Double, is Bool, is UInt, is Int64, is UInt64, is Float:
                cleaned[safeKey] = value
            case let number as NSNumber:
                cleaned[safeKey] = number
            default:
                // Dictionaries, dates, arbitrary objects: nothing legitimate
                // sends one, and a stringified object is exactly how content
                // would escape.
                cleaned[safeKey] = redactedMarker
                redacted += 1
            }
        }
        return (cleaned, redacted)
    }

    /// Four dot-separated groups of one to three digits. Rejects `10.0.1.42`
    /// while leaving a three-part version like `26.2.0` alone. A four-part
    /// build number would be caught too — a false positive worth taking,
    /// because it surfaces as a redaction count rather than as a leak.
    static func looksLikeIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isNumber)
        }
    }

    /// Three or more dot-separated components, none of them numeric — an
    /// Android package id (`com.example.app`), a bundle id, or a hostname.
    /// A dotted *version* has numeric components and is left alone.
    static func looksLikeReverseDNS(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && !part.allSatisfy(\.isNumber)
        }
    }
}
