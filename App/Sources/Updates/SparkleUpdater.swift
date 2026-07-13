#if !APPSTORE
import Combine
import Sparkle
import SwiftUI

/// UserDefaults key holding the display version of an update the user closed
/// or skipped instead of installing. RootView reads it on every launch and
/// resurfaces the update as a notification (with a Check for Updates button)
/// until it's installed — nothing is shown at dismiss time.
let pendingUpdateVersionKey = "pendingUpdateVersion"

/// Wraps Sparkle's updater and republishes whether a manual check is currently
/// allowed, so the "Check for Updates…" command can enable/disable itself.
/// As the updater delegate it also records an update the user closed or
/// skipped (see `pendingUpdateVersionKey`).
///
/// Lives in the App layer (never ADBKit) and is compiled out of any Mac App
/// Store build, which updates through the App Store instead.
@MainActor
final class UpdaterViewModel: NSObject, ObservableObject {
    @Published var canCheckForUpdates = false
    /// nil until a real EdDSA public key is embedded — without one, starting the
    /// updater fails its launch check and pops an error alert, so we hold off.
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        guard Self.signingKeyConfigured else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// True once `generate_keys`' output has replaced the project.yml placeholder.
    private static var signingKeyConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && key != "REPLACE_WITH_OUTPUT_OF_generate_keys"
    }
}

extension UpdaterViewModel: SPUUpdaterDelegate {
    /// Sparkle reports how the user resolved the update alert. Closing or
    /// skipping records the version for the once-per-launch reminder — no
    /// notification fires now, the user just declined the alert. Installing
    /// clears it.
    nonisolated func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .install:
            UserDefaults.standard.removeObject(forKey: pendingUpdateVersionKey)
        case .skip, .dismiss:
            UserDefaults.standard.set(updateItem.displayVersionString, forKey: pendingUpdateVersionKey)
        @unknown default:
            break
        }
    }
}

/// App-wide updater. A single Sparkle controller must own update scheduling, so
/// the menu, About view, and Settings all share this one instance.
enum SparkleUpdater {
    @MainActor static let shared = UpdaterViewModel()
}

/// The "Check for Updates…" menu command, greyed out while a check is in flight.
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
#endif
