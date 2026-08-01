/// The `.view` / `.system` feature ids that have a detail pane — one case per
/// routed id, and the only place those id strings are written.
///
/// `FeatureDetailView.detailByKind` switches over this exhaustively (no
/// `default`), so a case without a view fails the build, and
/// `FeatureDetailRouteTests` checks every case against `FeatureRegistry`. An
/// id with no case here falls through to `ComingSoonView`, which is silent at
/// build time — routing through this enum is what makes it testable.
///
/// Raw values are spelled out for every case because they *are* the contract
/// with the registry: renaming a case must not change the id it routes.
enum FeatureDetailRoute: String, CaseIterable {
    case reactNative = "react-native"
    case reactotron = "reactotron"
    case jsConsole = "js-console"
    case simulate = "simulate"
    case connection = "connection"
    case appManagement = "app-management"
    case deepLink = "deep-link"
    case logcat = "logcat"
    case iosLogs = "ios-logs"
    case permissions = "permissions"
    case appInfo = "app-info"
    case meminfo = "meminfo"
    case sandboxBrowser = "sandbox-browser"
    case deviceInfo = "device-info"
    case rootStatus = "root-status"
    case wifi = "wifi"
    case privateDns = "private-dns"
    case systemRestrictions = "system-restrictions"
    case devSettings = "dev-settings"
    case screenRecord = "screen-record"
    case videoEditor = "video-editor"
    case crashCatcher = "crash-catcher"
    case bugReport = "bug-report"
    case wirelessAdb = "wireless-adb"
    case customCommands = "custom-commands"
    case terminal = "terminal"
    case fileExplorer = "file-explorer"
    case apps = "apps"
    case installApp = "install-app"
    case apkStudio = "apk-studio"
    case apkInspector = "apk-inspector"
    case apkSign = "apk-sign"
    case apkDecompile = "apk-decompile"
    case aabConvert = "aab-convert"
    case fridaConsole = "frida-console"
    case emulators = "emulators"
    case performance = "performance"
    case networkSpeed = "network-speed"
    case scrcpy = "scrcpy"
    case apiClient = "api-client"
}
