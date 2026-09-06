import ADBKit
import Foundation

/// The crashes the Crash Catcher has collected, kept per window by
/// `FeatureStateStore` rather than as view `@State`.
///
/// The most expensive state in the app to lose: a fetch reads up to 16 MB of
/// logcat and parses it into Java, native, RN and ANR reports. Rebuilding that
/// because a tab moved to another window is a visible stall for something the
/// user had already waited for — and a crash buffer that has since rolled may
/// not even come back.
///
/// The *watch* is not here: it is live work owned by the view's task, and it
/// re-arms on the next appearance.
@MainActor
@Observable
final class CrashModel {
    var reports: [CrashReport] = []
    var selectedID: CrashReport.ID?
    /// A fetch has completed at least once, so an empty list means "no
    /// crashes" rather than "not looked yet".
    var fetched = false
    /// The last fetch errored (adb missing, device dropped mid-read). Cleared
    /// by the next successful fetch; drives the error empty state so a failed
    /// read never masquerades as "still checking" or "no crashes".
    var fetchFailed = false
    var kindFilter: CrashReport.Kind?
    var processFilter: String?
    var searchInput = ""
    var search = ""
    var showRaw = false
    /// Hide crashes at or before this timestamp on this serial — set by Clear
    /// buffer, which empties the crash buffer but can't touch the main-buffer
    /// fallback the same crashes would resurface from. Scoped to the serial it
    /// was set on so a device switch never hides another device's crashes.
    /// Logcat timestamps carry no year, so the lexicographic compare mis-hides
    /// only across a Dec→Jan rollover, and only until the view reopens.
    var clearedBefore: (serial: String, mark: String)?
}
