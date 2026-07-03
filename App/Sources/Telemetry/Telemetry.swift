import ADBKit
import Foundation
import PostHog
import Sentry

/// Crash reporting (Sentry) and product analytics (PostHog). Lives in the App
/// layer so ADBKit stays dependency-free and `swift test` stays clean.
///
/// Everything is anonymous: no device serials, package ids, file paths, IPs, or
/// command contents are ever sent — only which tool was used. Both are on by
/// default and opt-out in Settings → Privacy; the first-run consent disclosure
/// is deferred for the first few launches (gated in RootView).
@MainActor
final class Telemetry {
    static let shared = Telemetry()
    private init() {}

    static let crashReportingKey = "crashReportingEnabled"
    static let analyticsKey = "analyticsEnabled"

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
            #if DEBUG
            options.debug = true  // verbose Sentry logs in dev builds only
            #endif
        }
        sentryRunning = true
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
            config.personProfiles = .never               // fully anonymous — never identify
            config.errorTrackingConfig.autoCapture = false  // Sentry owns crash reporting
            #if DEBUG
            config.debug = true  // verbose PostHog logs in dev builds only
            #endif
            PostHogSDK.shared.setup(config)
            postHogReady = true
        }
        PostHogSDK.shared.optIn()
    }

    private func stopAnalytics() {
        guard postHogReady else { return }
        PostHogSDK.shared.optOut()
    }
}
