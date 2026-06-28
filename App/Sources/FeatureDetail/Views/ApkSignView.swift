import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Zipalign and sign an APK — with the embedded debug key for quick local
/// installs, an existing keystore, or a brand-new keystore created right here
/// for release builds. Passwords go to apksigner/keytool through a private temp
/// file, never the command line.
struct ApkSignView: View {
    @Environment(AppState.self) private var state
    @State private var inputURL: URL?
    @State private var keyMode: KeyMode = .debug
    @State private var keystoreURL: URL?
    @State private var storePassword = ""
    @State private var keyAlias = ""
    @State private var keyPassword = ""
    // New-keystore fields (keyMode == .create). Store/key passwords + alias are
    // shared with the existing-keystore fields, so a freshly created key is ready
    // to sign with no retyping.
    @State private var newKeystoreURL: URL?
    @State private var newCommonName = "Droidective"
    @State private var newOrganization = ""
    @State private var creating = false
    @State private var signing = false
    @State private var resultMessage: String?
    @State private var resultSchemes: [String] = []
    @State private var signedURL: URL?
    @State private var dropTargeted = false
    private let embedded: Bool

    enum KeyMode: String, CaseIterable, Identifiable {
        case debug = "Debug key"
        case existing = "Keystore"
        case create = "New keystore"
        var id: String { rawValue }
    }

    /// A non-nil `input` embeds the signer in APK Studio: it signs that APK (e.g.
    /// the one just recompiled) and drops its own drop zone / file picker.
    init(input: URL? = nil) {
        _inputURL = State(initialValue: input)
        embedded = input != nil
    }

    private var debugKeystore: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".android/debug.keystore")
    }

    private var canSign: Bool {
        guard inputURL != nil, !signing, !creating else { return false }
        switch keyMode {
        case .debug: return true
        case .existing: return keystoreURL != nil && !storePassword.isEmpty
        case .create: return false  // create first — that switches to .existing
        }
    }

    private var canCreate: Bool {
        !creating && newKeystoreURL != nil && !keyAlias.isEmpty
            && !newCommonName.isEmpty && !storePassword.isEmpty
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
                .font(.system(size: 46))
                .foregroundStyle(.brandAccent)
            Text("Drag an APK here to sign")
                .font(.title3.weight(.medium))
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
                Picker("Key", selection: $keyMode) {
                    ForEach(KeyMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                switch keyMode {
                case .debug: debugKeyNote
                case .existing: keystoreFields
                case .create: createFields
                }
            }
            Section {
                Button(signing ? "Signing…" : "Sign APK") { sign() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSign)
                if let resultMessage { resultRow(resultMessage) }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var debugKeyNote: some View {
        if !FileManager.default.fileExists(atPath: debugKeystore.path) {
            Label(
                "No debug keystore at ~/.android/debug.keystore yet — build any app once, or use your own keystore.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var keystoreFields: some View {
        LabeledContent("Keystore") {
            HStack {
                Text(keystoreURL?.lastPathComponent ?? "None").foregroundStyle(.textMuted)
                Button("Choose…") { chooseKeystore() }
            }
        }
        SecureField("Store password", text: $storePassword)
        TextField("Key alias (optional)", text: $keyAlias)
        SecureField("Key password (optional — defaults to store password)", text: $keyPassword)
    }

    @ViewBuilder private var createFields: some View {
        LabeledContent("Save as") {
            HStack {
                Text(newKeystoreURL?.lastPathComponent ?? "Choose a location…").foregroundStyle(.textMuted)
                Button("Choose…") { chooseNewKeystoreLocation() }
            }
        }
        TextField("Key alias", text: $keyAlias)
        TextField("Common name (CN)", text: $newCommonName)
        TextField("Organization (optional)", text: $newOrganization)
        SecureField("Store password", text: $storePassword)
        SecureField("Key password (optional — defaults to store password)", text: $keyPassword)
        Button(creating ? "Creating…" : "Create keystore") { createKeystore() }
            .disabled(!canCreate)
        Text("Creates a self-signed RSA-2048 keystore (valid ~27 years) and selects it for signing.")
            .font(.caption).foregroundStyle(.textMuted)
    }

    @ViewBuilder private func resultRow(_ message: String) -> some View {
        if signedURL != nil {
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                if !resultSchemes.isEmpty {
                    Text("Verified: " + resultSchemes.map { $0.uppercased() }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.textMuted)
                }
                Button("Reveal in Finder") {
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

    private func chooseKeystore() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { keystoreURL = panel.url }
    }

    private func chooseNewKeystoreLocation() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(keyAlias.isEmpty ? "release" : keyAlias).jks"
        panel.canCreateDirectories = true
        panel.directoryURL = try? ScreenCaptureService.ensureCaptureDir()
        if panel.runModal() == .OK { newKeystoreURL = panel.url }
    }

    private func createKeystore() {
        guard let newKeystoreURL else { return }
        let spec = NewKeystore(
            path: newKeystoreURL.path, alias: keyAlias, storePassword: storePassword,
            keyPassword: keyPassword.isEmpty ? nil : keyPassword,
            commonName: newCommonName, organization: newOrganization.isEmpty ? nil : newOrganization)
        creating = true
        resultMessage = nil
        Task {
            do {
                _ = try await state.env.engine.apkSigning.createKeystore(spec)
                keystoreURL = newKeystoreURL
                keyMode = .existing  // the new key's passwords/alias are already filled in
                state.showToast(Toast(
                    message: "Created \(newKeystoreURL.lastPathComponent)", ok: true, revealPath: newKeystoreURL.path))
            } catch {
                resultMessage = error.localizedDescription
                signedURL = nil
            }
            creating = false
        }
    }

    private func sign() {
        guard let inputURL else { return }
        let output = inputURL.deletingPathExtension().path + "-signed.apk"
        let credentials: KeystoreCredentials
        switch keyMode {
        case .debug:
            credentials = .debug(keystorePath: debugKeystore.path)
        case .existing, .create:
            guard let keystoreURL else { return }
            credentials = KeystoreCredentials(
                keystorePath: keystoreURL.path, storePassword: storePassword,
                keyAlias: keyAlias.isEmpty ? nil : keyAlias,
                keyPassword: keyPassword.isEmpty ? nil : keyPassword)
        }
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
