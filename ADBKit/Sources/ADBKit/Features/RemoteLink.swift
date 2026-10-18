import Foundation

/// How the app treats a phone it reaches over Tailscale rather than over USB
/// or the local network: a slower link, and one a settings change on the phone
/// can cut with no way to restore it from here.
public enum RemoteLink {
    // MARK: - Mirror preset

    /// The remote preset's caps: 2 Mbit/s, 1280 px, 30 fps. scrcpy's own
    /// 8 Mbit/s default does not slow down for a slow link — it backs up, and
    /// the mirror falls further behind the phone the longer it runs.
    public static let mirrorBitRate = 2_000_000
    public static let mirrorMaxSize = 1280
    public static let mirrorMaxFps = 30

    /// `params` capped to the remote preset when `serial` is a tailnet device,
    /// unchanged otherwise. Caps only ever lower: a Mirror Wall tile already
    /// asking for 640 px keeps its 640.
    public static func mirrorParams(_ params: ScrcpyServerParams, serial: String) -> ScrcpyServerParams {
        guard TailscalePeers.isTailnet(serial: serial) else { return params }
        var capped = params
        capped.videoBitRate = cap(params.videoBitRate, at: mirrorBitRate)
        capped.maxSize = cap(params.maxSize, at: mirrorMaxSize)
        capped.maxFps = cap(params.maxFps, at: mirrorMaxFps)
        return capped
    }

    /// 0 means "the server's default" for all three, which is above every cap.
    private static func cap(_ value: Int, at ceiling: Int) -> Int {
        value > 0 ? min(value, ceiling) : ceiling
    }

    // MARK: - Asking first

    /// Whether running `featureID` on `serials` should ask first: the feature
    /// can take a phone off the network (`FeatureRegistry.remoteLinkWarnings`)
    /// and at least one target is reached over Tailscale.
    public static func asksFirst(featureID: String, serials: [String]) -> Bool {
        FeatureRegistry.remoteLinkWarnings[featureID] != nil
            && serials.contains(where: TailscalePeers.isTailnet(serial:))
    }

    /// The question, or nil when there is nothing to ask.
    public static func confirmation(
        featureID: String, serials: [String], deviceName: String
    ) -> (title: String, message: String)? {
        guard asksFirst(featureID: featureID, serials: serials),
              let warning = FeatureRegistry.remoteLinkWarnings[featureID]
        else { return nil }
        return (
            "\(deviceName) is connected over Tailscale",
            "\(warning) If the link drops, reconnecting needs the phone in hand.")
    }
}
