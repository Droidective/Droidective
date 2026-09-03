import ADBKit
import AppKit
import Foundation
import PostHog
import Sentry

/// Crash reporting (Sentry) and product analytics (PostHog). Lives in the App
/// layer so ADBKit stays dependency-free and `swift test` stays clean.
///
/// Anonymous by design: no device serials, package ids, file paths, IPs, or
/// command contents are ever sent — only which feature was used and the app's
/// own resource numbers. The only stable identifier is a random per-install
/// UUID (`deviceID`, no PII), set on both sinks so distinct-install counts
/// agree and a Sentry crash/hang cross-references the same install's PostHog
/// usage. Both sinks are on by default and opt-out in
/// Settings → Privacy; the first-run consent disclosure is deferred for the
/// first few launches (gated in RootView).
@MainActor
final class Telemetry {
    static let shared = Telemetry()
    private init() {}

    static let crashReportingKey = "crashReportingEnabled"
    static let analyticsKey = "analyticsEnabled"
    static let deviceIDKey = "analyticsDeviceID"

    /// The feature currently in the foreground and when it got there, so a switch
    /// can report the prior feature's dwell time.
    private var activeFeatureID: String?
    private var activeSince: Date?

    /// Launch is reported from RootView's appear, which re-fires when the root
    /// re-keys on an appearance change — gate it to once per process.
    private var launchTracked = false

    /// A random, persistent, non-personal id for this install. Generated once and
    /// reused so distinct-user and retention analytics work without any PII.
    private static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceIDKey)
        return id
    }

    /// Defaults ON. Opt-out in Settings → Privacy.
    var crashReportingEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.crashReportingKey) as? Bool ?? true
    }

    /// Defaults ON. Opt-out in Settings → Privacy.
    var analyticsEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.analyticsKey) as? Bool ?? true
    }

    private var sentryRunning = false
    private var postHogReady = false

    /// Apply the stored consent. Call once at launch.
    func start() {
        if crashReportingEnabled { startSentry() }
        if analyticsEnabled { startAnalytics() }
        trackAppActivity()
    }

    /// Keep an `app_active` flag on every event from both sinks. Hangs and
    /// perf incidents that fire while the user is in another app are a
    /// different bug class (work running behind the user's back) than ones
    /// mid-interaction — this one flag separates them at a glance, where
    /// before it took manually correlating event sequences.
    private func trackAppActivity() {
        let update: @MainActor (Bool) -> Void = { [weak self] active in
            guard let self else { return }
            if self.crashReportingEnabled, self.sentryRunning {
                SentrySDK.configureScope { $0.setTag(value: active ? "true" : "false", key: "app_active") }
            }
            if self.analyticsEnabled, self.postHogReady {
                PostHogSDK.shared.register(["app_active": active])
            }
        }
        // `NSApp` is an implicitly-unwrapped global that stays nil until
        // NSApplication exists, and this runs from `ADTApp.init()` — which
        // predates it. Optional-chain the seed: no app yet means not active
        // yet, and `didBecomeActiveNotification` corrects it at launch.
        update(NSApp?.isActive ?? false)
        for (name, active) in [
            (NSApplication.didBecomeActiveNotification, true),
            (NSApplication.didResignActiveNotification, false),
        ] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                // The observer queue is main; hop is compile-time ceremony.
                MainActor.assumeIsolated { update(active) }
            }
        }
    }

    // MARK: - Diagnostic context

    /// PostHog super-property names registered per diagnostic key, so clearing
    /// a context unregisters exactly what it registered.
    private var diagnosticKeys: [String: [String]] = [:]

    /// Attach always-on diagnostic state that rides every *subsequent* event
    /// on both sinks — a Sentry context block and prefixed PostHog
    /// super-properties. Costs no extra event volume: the values only ship
    /// attached to events that were being sent anyway (hangs, crashes, perf
    /// incidents), which is what makes root causes readable from a single
    /// event on the free plans. Pass nil to clear. Callers should publish on
    /// state *changes*, not on a hot path — every call crosses both SDKs.
    func setDiagnosticContext(_ key: String, _ values: [String: Any]?) {
        if crashReportingEnabled, sentryRunning {
            SentrySDK.configureScope { scope in
                if let values {
                    scope.setContext(value: values, key: key)
                } else {
                    scope.removeContext(key: key)
                }
            }
        }
        if let values {
            guard analyticsEnabled, postHogReady else { return }
            var flat: [String: Any] = [:]
            for (name, value) in values { flat["\(key)_\(name)"] = value }
            diagnosticKeys[key] = Array(flat.keys)
            PostHogSDK.shared.register(flat)
        } else if postHogReady {
            // Clearing is deliberately not gated on the consent toggle:
            // super-properties persist in the SDK across opt-out/opt-in, so
            // a clear that lands while opted out must still unregister —
            // otherwise a re-opt-in resurrects a dead session's context on
            // every event.
            for name in diagnosticKeys.removeValue(forKey: key) ?? [] {
                PostHogSDK.shared.unregister(name)
            }
        }
    }

    /// A Sentry breadcrumb — free until an event ships, then it's the
    /// timeline explaining that event. For state transitions worth seeing
    /// leading up to a hang or crash (session connects, bursts, teardowns).
    func breadcrumb(category: String, _ message: String) {
        guard crashReportingEnabled, sentryRunning else { return }
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Ship one structured log line. Unlike a breadcrumb this stands on its
    /// own — it arrives whether or not an event ever ships, which is what
    /// makes a slow operation visible before it becomes a hang report.
    ///
    /// Called only by `AppLog`, which owns the rate limit and the local
    /// `os_log` half. `attributes` carries numbers and feature ids, never
    /// paths, URLs or content — same promise as every other sink here.
    func log(_ level: AppLog.Level, _ message: String, _ attributes: [String: Any]) {
        guard crashReportingEnabled, sentryRunning else { return }
        let logger = SentrySDK.logger
        switch level {
        case .debug: logger.debug(message, attributes: attributes)
        case .info: logger.info(message, attributes: attributes)
        case .warn: logger.warn(message, attributes: attributes)
        case .error: logger.error(message, attributes: attributes)
        }
    }

    func setCrashReporting(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.crashReportingKey)
        if enabled { startSentry() } else { stopSentry() }
    }

    func setAnalytics(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.analyticsKey)
        if enabled { startAnalytics() } else { stopAnalytics() }
    }

    /// Record an anonymous product-analytics event. No-op unless opted in.
    func track(_ event: String, _ properties: [String: Any] = [:]) {
        guard analyticsEnabled, postHogReady else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    // MARK: - Feature usage

    /// One engagement with a feature — opening a view/hub pane or invoking an
    /// action. Fired from AppState's two choke points (`requestFeature`, `run`),
    /// so it covers every feature uniformly (the old `feature_used` only saw
    /// actions). `kind` groups views vs. the action variants.
    func trackFeatureUsed(_ id: String, kind: String) {
        track("feature_used", ["feature": id, "kind": kind])
    }

    /// The foreground feature changed. Reports the prior feature's dwell time,
    /// then tags every subsequent crash, hang, and analytics event with the new
    /// active feature — so incidents attribute to whatever was on screen. Safe to
    /// call regardless of consent; each sink guards its own toggle.
    func featureBecameActive(_ id: String?) {
        let feature = id ?? "none"
        if let previous = activeFeatureID, let since = activeSince, previous != feature {
            track("feature_foreground", [
                "feature": previous,
                "seconds": Int(Date().timeIntervalSince(since).rounded()),
            ])
        }
        activeFeatureID = feature
        activeSince = Date()

        if crashReportingEnabled, sentryRunning {
            SentrySDK.configureScope { $0.setTag(value: feature, key: "active_feature") }
            let crumb = Breadcrumb(level: .info, category: "navigation")
            crumb.message = "feature → \(feature)"
            SentrySDK.addBreadcrumb(crumb)
        }
        if analyticsEnabled, postHogReady {
            PostHogSDK.shared.register(["active_feature": feature])
        }
    }

    /// The set of open (kept-alive) feature tabs changed. Tags every crash and
    /// hang with what else is running: a hidden tab's stream can be the real
    /// workload while `active_feature` names whatever is on screen, so the tag
    /// pair is what attributes an incident correctly.
    func openFeaturesChanged(_ ids: [String]) {
        let joined = ids.isEmpty ? "none" : ids.sorted().joined(separator: ",")
        // The count as its own tag, because it is the figure that explained
        // the largest hang issue and the joined list cannot be aggregated on:
        // grouping DROIDECTIVE-MAC-B by `open_features` produced one row per
        // distinct tab *combination*, so the finding — that ~4000 of 5087
        // events were a handful of users with 9 to 18 tabs mounted — had to be
        // read off six unrelated rows. Every open tab stays mounted, so this
        // is a direct measure of how much tree each layout pass walks.
        let count = String(ids.count)
        if crashReportingEnabled, sentryRunning {
            SentrySDK.configureScope {
                $0.setTag(value: joined, key: "open_features")
                $0.setTag(value: count, key: "open_feature_count")
            }
        }
        if analyticsEnabled, postHogReady {
            PostHogSDK.shared.register(["open_features": joined, "open_feature_count": ids.count])
        }
    }

    // MARK: - Who & session

    /// Version/OS/arch describing this install — registered as super-properties
    /// so every event can be sliced by app version, macOS, and CPU.
    private static var baseProperties: [String: Any] {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return [
            "app_version": info?["CFBundleShortVersionString"] as? String ?? "unknown",
            "app_build": info?["CFBundleVersion"] as? String ?? "unknown",
            "macos_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "mac_arch": arch,
        ]
    }

    /// Attach the user's role to every subsequent event, so all analytics can be
    /// segmented by who's using the app. `nil` (chose "everything") reads as
    /// "unset". Idempotent — call at launch and whenever the role changes.
    func applyRole(_ role: String?) {
        guard analyticsEnabled, postHogReady else { return }
        PostHogSDK.shared.register(["role": role ?? "unset"])
    }

    /// One session-start event per launch, carrying the running launch count so
    /// activation and retention are measurable.
    func trackAppLaunched(launchCount: Int) {
        guard !launchTracked else { return }
        launchTracked = true
        track("app_launched", ["launch_count": launchCount])
    }

    /// The user picked or switched roles (or chose "everything"). `isChange`
    /// separates a first pick from a later switch.
    func trackRoleChosen(_ role: String, isChange: Bool) {
        track("role_selected", ["role": role, "is_change": isChange])
    }

    /// A device became visible. Carries only connection-shape flags — no
    /// device identity (model, OS version, serial), matching the app's "no
    /// device data" promise in Settings ▸ Privacy and the privacy policy.
    func trackDeviceConnected(isEmulator: Bool, isWireless: Bool) {
        track("device_connected", [
            "is_emulator": isEmulator,
            "is_wireless": isWireless,
        ])
        if crashReportingEnabled, sentryRunning {
            let crumb = Breadcrumb(level: .info, category: "device")
            let kind = isEmulator ? "emulator" : (isWireless ? "wireless" : "usb")
            crumb.message = "connected: \(kind)"
            SentrySDK.addBreadcrumb(crumb)
        }
    }

    // MARK: - Performance

    /// A closed window of per-feature resource use (from `FeaturePerfAggregator`)
    /// — a baseline distribution, not just the threshold spikes below.
    func reportFeaturePerf(_ record: FeaturePerfRecord) {
        track("feature_perf", [
            "feature": record.feature,
            "seconds": Int(record.seconds.rounded()),
            "samples": record.samples,
            "avg_cpu": Int(record.averageCPUPercent.rounded()),
            "peak_cpu": Int(record.peakCPUPercent.rounded()),
            "avg_mem_mb": Int((record.averageMemoryBytes / 1_048_576).rounded()),
            "peak_mem_mb": Int((Double(record.peakMemoryBytes) / 1_048_576).rounded()),
        ])
    }

    // MARK: - Performance incidents

    /// Report sustained app resource overuse (or its recovery) from the
    /// performance monitor. An incident becomes a PostHog `app_perf_incident`
    /// event and a Sentry warning fingerprinted per metric + active feature,
    /// so each resource hog groups into its own issue; recovery sends the
    /// peak/duration follow-up and leaves a Sentry breadcrumb. Each sink
    /// respects its own consent toggle. Only feature ids and resource numbers
    /// are sent — nothing device- or user-identifying.
    func reportResourceEvent(_ event: ResourceEvent, context: PerformanceMonitor.FeatureContext) {
        let feature = context.activeFeature ?? "none"
        switch event {
        case .began(let metric, let value, let limit):
            track("app_perf_incident", [
                "metric": metric.rawValue,
                "value": chartValue(metric, value),
                "limit": chartValue(metric, limit),
                "feature": feature,
                "open_features": context.openFeatures,
            ])
            guard crashReportingEnabled, sentryRunning else { return }
            let sentryEvent = Sentry.Event(level: .warning)
            sentryEvent.message = SentryMessage(
                formatted: "High \(label(metric)): \(readable(metric, value)) while \(feature) is active")
            sentryEvent.fingerprint = ["app-perf", metric.rawValue, feature]
            sentryEvent.tags = ["perf_metric": metric.rawValue, "perf_feature": feature]
            sentryEvent.extra = [
                "value": readable(metric, value),
                "limit": readable(metric, limit),
                "open_features": context.openFeatures.joined(separator: ", "),
            ]
            SentrySDK.capture(event: sentryEvent)
        case .ended(let metric, let peak, let seconds):
            track("app_perf_recovered", [
                "metric": metric.rawValue,
                "peak": chartValue(metric, peak),
                "duration_seconds": Int(seconds.rounded()),
                "feature": feature,
            ])
            guard crashReportingEnabled, sentryRunning else { return }
            let crumb = Breadcrumb(level: .info, category: "app.perf")
            crumb.message =
                "\(label(metric)) recovered — peak \(readable(metric, peak)) over \(Int(seconds.rounded()))s"
            SentrySDK.addBreadcrumb(crumb)
        }
    }

    /// Chartable number for PostHog: CPU in percent, memory in MB.
    private func chartValue(_ metric: ResourceMetric, _ value: Double) -> Int {
        switch metric {
        case .cpu: Int(value.rounded())
        case .memory: Int((value / 1_048_576).rounded())
        }
    }

    private func readable(_ metric: ResourceMetric, _ value: Double) -> String {
        switch metric {
        case .cpu: "\(Int(value.rounded()))%"
        case .memory: ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
        }
    }

    private func label(_ metric: ResourceMetric) -> String {
        switch metric {
        case .cpu: "CPU"
        case .memory: "memory"
        }
    }

    // MARK: - Sentry (crashes + performance)

    private func startSentry() {
        guard !sentryRunning, TelemetryConfig.sentryConfigured else { return }
        SentrySDK.start { options in
            options.dsn = TelemetryConfig.sentryDSN
            options.sendDefaultPii = false
            options.tracesSampleRate = 0.2
            options.enableUncaughtNSExceptionReporting = true
            // App-hang tracking is on by default (2s main-thread stall). Both
            // hangs and crashes inherit the `active_feature` scope tag set in
            // `featureBecameActive`, so they group by the feature on screen.
            options.appHangTimeoutInterval = 2
            // Structured logs. Before this the only diagnostics that left the
            // machine were tags, breadcrumbs and a stack, so the Sentry logs
            // view was empty and `PerfLog`'s slow-operation warnings — the
            // ones that name what actually stalled — reached nobody but a
            // developer with Console attached. Diagnosing the largest hang
            // issue (DROIDECTIVE-MAC-B) took five aggregate queries against
            // tags because of it. See `AppLog`, which is the only writer.
            options.enableLogs = true
            // Sentry captures every 5xx a URLSession sees by default. That is
            // wrong for this app twice over.
            //
            // It is noise: every HTTP client here talks either to a dev server
            // on the user's own Mac — Metro on 8081, whose `/symbolicate`
            // answers 500 for any frame it can't map, a routine outcome
            // `MetroSymbolicator` already handles and circuit-breaks — or to a
            // server the *user* chose in API Testing. Neither is a Droidective
            // bug. Metro alone produced 40 events across 9 users
            // (DROIDECTIVE-MAC-6D) reported as `-[SentryStacktraceBuilder
            // buildStacktraceForCurrentThread]`, which names the reporter
            // rather than anything in this app.
            //
            // And it leaks: a captured request carries its URL, so a user
            // testing their own API against a 5xx would ship that URL here.
            // Settings ▸ Privacy and the privacy policy both promise no URLs
            // or paths are ever sent, and `sendDefaultPii = false` does not
            // cover this.
            //
            // Nothing is lost by turning it off: the only remote HTTP the app
            // makes on its own account is managed-tool downloads and the
            // Sparkle appcast, and both already surface their failure to the
            // user with the real error.
            options.enableCaptureFailedRequests = false
            // Sampled continuous profiling tied to traced spans — function-level
            // "what burned the CPU" for the sampled sessions.
            options.configureProfiling = { profiling in
                profiling.lifecycle = .trace
                profiling.sessionSampleRate = 0.2
            }
            // Mirror detected app hangs into PostHog so they sit alongside usage
            // (the `active_feature` super-property rides along automatically).
            options.beforeSend = { event in
                if Self.isAppHang(event) {
                    Task { @MainActor in Telemetry.shared.track("app_hang") }
                }
                return event
            }
            #if DEBUG
            options.debug = true  // verbose Sentry logs in dev builds only
            #endif
        }
        // The same anonymous per-install UUID PostHog identifies with, so
        // distinct-install counts match across sinks and a Sentry incident can
        // be joined to that install's PostHog usage. Not PII — random, local.
        let user = User(userId: Self.deviceID)
        SentrySDK.setUser(user)
        sentryRunning = true
    }

    /// Whether a Sentry event is an app-hang report, by its exception mechanism.
    private nonisolated static func isAppHang(_ event: Sentry.Event) -> Bool {
        event.exceptions?.contains { exception in
            let mechanism = exception.mechanism?.type ?? ""
            let type = exception.type ?? ""
            return mechanism.localizedCaseInsensitiveContains("apphang")
                || type.localizedCaseInsensitiveContains("hang")
        } ?? false
    }

    private func stopSentry() {
        guard sentryRunning else { return }
        SentrySDK.close()
        sentryRunning = false
    }

    // MARK: - PostHog (opt-in analytics)

    private func startAnalytics() {
        guard TelemetryConfig.analyticsConfigured else { return }
        if !postHogReady {
            let config = PostHogConfig(projectToken: TelemetryConfig.postHogKey, host: TelemetryConfig.postHogHost)
            // Identify by a random per-install UUID (no PII) so distinct-user,
            // retention, and funnel analytics work while staying anonymous.
            config.personProfiles = .identifiedOnly
            config.errorTrackingConfig.autoCapture = false  // Sentry owns crash reporting
            #if DEBUG
            config.debug = true  // verbose PostHog logs in dev builds only
            #endif
            PostHogSDK.shared.setup(config)
            postHogReady = true
        }
        PostHogSDK.shared.optIn()
        PostHogSDK.shared.identify(Self.deviceID)
        PostHogSDK.shared.register(Self.baseProperties)
    }

    private func stopAnalytics() {
        guard postHogReady else { return }
        PostHogSDK.shared.optOut()
    }
}
