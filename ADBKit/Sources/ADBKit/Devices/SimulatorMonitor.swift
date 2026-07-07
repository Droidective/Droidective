import Foundation

/// iOS Simulator discovery: polls `simctl list -j devices`, caches briefly,
/// and pushes booted-simulator changes to subscribers — DeviceMonitor's
/// counterpart. Without Xcode installed it publishes an empty list (the
/// missing-xcrun check is a cheap filesystem probe, so idle polling costs
/// nothing on Android-only machines).
public actor SimulatorMonitor {
    private static let cacheTTL: Duration = .seconds(3)

    private let client: SimctlClient
    private var cache: (simulators: [Simulator], at: ContinuousClock.Instant)?
    private var continuations: [UUID: AsyncStream<[Device]>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var lastPublished: [Device]?
    private var pollInterval: Duration = .seconds(3)

    public init(client: SimctlClient) {
        self.client = client
    }

    /// All simulators (any state), using a short-lived cache.
    public func list(force: Bool = false) async -> [Simulator] {
        if !force, let cache, ContinuousClock().now - cache.at < Self.cacheTTL {
            return cache.simulators
        }
        guard let result = try? await client.run(["list", "-j", "devices"]), result.succeeded else {
            cache = ([], ContinuousClock().now)
            return []
        }
        let simulators = SimulatorListParser.parse(result.stdout)
        cache = (simulators, ContinuousClock().now)
        return simulators
    }

    /// Invalidate the cache (call after boot/shutdown) and refresh subscribers.
    public func invalidate() async {
        cache = nil
        await pollOnce()
    }

    /// Continuous booted-simulator updates; yields whenever the set changes.
    /// Starts the polling loop on first subscription.
    public func updates(interval: Duration = .seconds(3)) -> AsyncStream<[Device]> {
        let id = UUID()
        let stream = AsyncStream<[Device]> { continuation in
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
            self.continuations[id] = continuation
            if let lastPublished {
                continuation.yield(lastPublished)
            }
        }
        startPollingIfNeeded(interval: interval)
        return stream
    }

    /// Adjust the polling cadence at runtime — DeviceMonitor's counterpart, so
    /// the app can widen it while backgrounded instead of spawning `simctl
    /// list` every 3s forever. Takes effect on the next loop iteration.
    public func setPollInterval(_ interval: Duration) {
        pollInterval = interval
    }

    private func startPollingIfNeeded(interval: Duration) {
        pollInterval = interval
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    private func pollOnce() async {
        let devices = SimulatorListParser.devices(from: await list(force: true))
        if devices != lastPublished {
            lastPublished = devices
            for continuation in continuations.values {
                continuation.yield(devices)
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
        if continuations.isEmpty {
            pollTask?.cancel()
            pollTask = nil
        }
    }
}
