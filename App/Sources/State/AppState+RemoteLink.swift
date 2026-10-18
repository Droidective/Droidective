import ADBKit
import SwiftUI

/// Asking before a feature that can take a phone off the network runs on one
/// reached over Tailscale. Which features, and the sentence saying how, are
/// `FeatureRegistry.remoteLinkWarnings`; whether to ask is
/// `RemoteLink.asksFirst`. This is the App half: name the device, park the
/// action, and present the question where the user asked for it.
extension AppState {
    /// Runs `perform` at once — or, when `featureID` can take a phone off the
    /// network and `serials` includes one reached over Tailscale, parks it in
    /// `prompt` until the user confirms (`View.remoteLinkConfirmation`).
    func askingBeforeCuttingRemoteLink(
        _ featureID: String, serials: [String], confirmLabel: String,
        prompt: Binding<RemoteLinkPrompt?>, perform: @escaping @MainActor () -> Void
    ) {
        guard let question = remoteLinkQuestion(featureID, serials: serials) else {
            perform()
            return
        }
        prompt.wrappedValue = RemoteLinkPrompt(
            title: question.title, message: question.message,
            confirmLabel: confirmLabel, perform: perform)
    }

    /// The question to ask, or nil when there is nothing to ask. Named after
    /// the first tailnet device among `serials`, which is the one at risk.
    func remoteLinkQuestion(
        _ featureID: String, serials: [String]
    ) -> (title: String, message: String)? {
        let remote = serials.first(where: TailscalePeers.isTailnet(serial:))
        let name = remote.map { serial in
            devices.first { $0.serial == serial }.map(deviceDisplayName) ?? serial
        } ?? ""
        return RemoteLink.confirmation(featureID: featureID, serials: serials, deviceName: name)
    }
}

/// A question parked until the user answers it. See
/// `AppState.askingBeforeCuttingRemoteLink`.
struct RemoteLinkPrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmLabel: String
    let perform: @MainActor () -> Void
}

extension View {
    /// Presents a parked `RemoteLinkPrompt` as a confirmation dialog. Attached
    /// by the view that asks, so it works inside a sheet as well as a pane.
    func remoteLinkConfirmation(_ prompt: Binding<RemoteLinkPrompt?>) -> some View {
        modifier(RemoteLinkConfirmation(prompt: prompt))
    }
}

private struct RemoteLinkConfirmation: ViewModifier {
    @Binding var prompt: RemoteLinkPrompt?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            prompt?.title ?? "",
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            titleVisibility: .visible,
            presenting: prompt
        ) { prompt in
            Button(prompt.confirmLabel, role: .destructive) { prompt.perform() }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
    }
}
