import ADBKit
import Foundation
import PostHog
import Sentry

/// Crash reporting (Sentry) and product analytics (PostHog). Lives in the App
/// layer so ADBKit stays dependency-free and `swift test` stays clean.
///
/// Anonymous by design: no device serials, package ids, file paths, IPs, or
/// command contents are ever sent — only which feature was used and the app's
/// own resource numbers. The only stable identifier is a random per-install
/// UUID (`deviceID`, no PII), which lets PostHog count distinct installs,
/// retention, and funnels. Both sinks are on by default and opt-out in
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
        }
        if analyticsEnabled, postHogReady {
            PostHogSDK.shared.register(["active_feature": feature])
        }
    }

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
    }

    private func stopAnalytics() {
        guard postHogReady else { return }
        PostHogSDK.shared.optOut()
    }
}
