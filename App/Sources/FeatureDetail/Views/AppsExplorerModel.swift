import ADBKit
import Foundation

/// The Apps explorer's list and what the user has done with it, kept per window
/// by `FeatureStateStore` rather than as view `@State`.
///
/// Reading every installed app off a device takes a couple of seconds and a
/// handful of `adb shell` round trips, and the view used to do it again on every
/// mount — so a tab moving to another window dropped the list, the search, the
/// scope and the selected app, and made the user wait for a list they were
/// already looking at. `loadedSerial` records which device the list came from,
/// so a remount asking about the same one keeps it while a device switch still
/// re-reads.
@MainActor
@Observable
final class AppsExplorerModel {
    /// Every installed app, nil until the first read finishes.
    var apps: [AppListing]?
    /// Enabled/disabled/removed per package, read alongside the list.
    var states: [String: AppLifecycle] = [:]
    /// The device `apps` was read from.
    var loadedSerial: String?

    var search = ""
    var scope = AppsScope.user
    var selectedPackage: String?
    /// Packages an uninstall attempt proved can't actually be removed (it
    /// reported success but the package stayed). Their Uninstall button is
    /// dropped, leaving Disable.
    var notRemovable: Set<String> = []
}

/// Which apps the explorer lists.
enum AppsScope: String, CaseIterable {
    case all = "All"
    case user = "User"
    case system = "System"
}
