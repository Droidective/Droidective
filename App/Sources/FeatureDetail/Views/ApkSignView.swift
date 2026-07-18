import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Zipalign and sign an APK — with the embedded debug key for quick local
/// installs, an existing keystore, or a brand-new keystore created right here
/// for release builds (the key choice UI is the shared `SigningKeyFields`).
/// Passwords go to apksigner/keytool through a private temp file, never the
/// command line.
struct ApkSignView: View {
    @Environment(AppState.self) private var state
    @State private var inputURL: URL?
    @State private var keyModel = SigningKeyModel()
    @State private var signing = false
    @State private var resultMessage: String?
    @State private var resultSchemes: [String] = []
    @State private var signedURL: URL?
    @State private var dropTargeted = false
    private let embedded: Bool

    /// A non-nil `input` embeds the signer in APK Studio: it signs that APK (e.g.
    /// the one just recompiled) and drops its own drop zone / file picker.
    init(input: URL? = nil) {
        _inputURL = State(initialValue: input)
        embedded = input != nil
    }

    private var canSign: Bool {
        inputURL != nil && !signing && !keyModel.creating && keyModel.isComplete
    }

    var body: some View {
        Group {
            if inputURL == nil { dropZone } else { form }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "signature")
                .font(.app(size: 46))
                .foregroundStyle(.brandAccent)
            Text("Drag an APK here to sign")
                .font(.app(.title3).weight(.medium))
            Button("Choose APK…") { choose() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bgSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    dropTargeted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.borderSubtle),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [7])
                )
                .padding(24)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let apk = urls.first(where: { $0.pathExtension.lowercased() == "apk" }) else { return false }
            stage(apk)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section("APK") {
                LabeledContent("File", value: inputURL?.lastPathComponent ?? "")
                if !embedded {
                    Button("Choose a different APK…") { choose() }
                }
            }
            Section("Signing key") {
                SigningKeyFields(model: keyModel)
            }
            Section {
                Button(signing ? "Signing…" : "Sign APK") { sign() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSign)
                if let resultMessage { resultRow(resultMessage) }
            }
        }
        .formStyle(.grouped)
        .translucentListBackground()
    }

    @ViewBuilder private func resultRow(_ message: String) -> some View {
        if signedURL != nil {
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                if !resultSchemes.isEmpty {
                    Text("Verified: " + resultSchemes.map { $0.uppercased() }.joined(separator: ", "))
                        .font(.app(.caption)).foregroundStyle(.textMuted)
                }
                Button("Open in Finder") {
                    if let signedURL { NSWorkspace.shared.activateFileViewerSelecting([signedURL]) }
                }
            }
        } else {
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    // MARK: - Actions

    private func stage(_ url: URL) {
        inputURL = url
        resultMessage = nil
        signedURL = nil
        resultSchemes = []
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { stage(url) }
    }

    private func sign() {
        guard let inputURL, let credentials = keyModel.explicitCredentials else { return }
        let output = inputURL.deletingPathExtension().path + "-signed.apk"
        signing = true
        Task {
            do {
                let result = try await state.env.engine.apkSigning.sign(
                    input: inputURL.path, output: output, credentials: credentials)
                resultSchemes = result.signature?.schemes ?? []
                signedURL = URL(fileURLWithPath: output)
                resultMessage = result.message
            } catch {
                resultMessage = error.localizedDescription
                signedURL = nil
            }
            signing = false
        }
    }
}
