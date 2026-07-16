import ADBKit
import AppKit
import SwiftUI

/// The signing-key choice shared by the APK signer and the AAB converter:
/// the embedded debug key, an existing keystore, or a brand-new keystore
/// created in place (which selects itself for signing). The fields render
/// with `SigningKeyFields`; passwords reach apksigner/keytool/bundletool
/// through private temp files, never the command line.
@MainActor @Observable
final class SigningKeyModel {
    enum Mode: String, CaseIterable, Identifiable {
        case debug = "Debug key"
        case existing = "Keystore"
        case create = "New keystore"
        var id: String { rawValue }
    }

    var mode: Mode = .debug
    var keystoreURL: URL?
    var storePassword = ""
    var keyAlias = ""
    var keyPassword = ""
    // New-keystore fields (mode == .create). Store/key passwords + alias are
    // shared with the existing-keystore fields, so a freshly created key is
    // ready to sign with no retyping.
    var newKeystoreURL: URL?
    var newCommonName = "Droidective"
    var newOrganization = ""
    var creating = false
    var createError: String?

    static let debugKeystore = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".android/debug.keystore")

    var debugKeystoreExists: Bool {
        FileManager.default.fileExists(atPath: Self.debugKeystore.path)
    }

    /// Ready to sign with. `.create` never is — creating the keystore
    /// switches the mode to `.existing` first.
    var isComplete: Bool {
        switch mode {
        case .debug: return true
        case .existing: return keystoreURL != nil && !storePassword.isEmpty
        case .create: return false
        }
    }

    var canCreate: Bool {
        !creating && newKeystoreURL != nil && !keyAlias.isEmpty
            && !newCommonName.isEmpty && !storePassword.isEmpty
    }

    /// Credentials with the debug key spelled out — for apksigner, which has
    /// no debug fallback of its own. Nil until `isComplete`.
    var explicitCredentials: KeystoreCredentials? {
        switch mode {
        case .debug:
            return .debug(keystorePath: Self.debugKeystore.path)
        case .existing, .create:
            return releaseCredentials
        }
    }

    /// Credentials only when a release keystore is picked — for bundletool,
    /// which falls back to `~/.android/debug.keystore` by itself on nil.
    var releaseCredentials: KeystoreCredentials? {
        guard mode == .existing, let keystoreURL, !storePassword.isEmpty else { return nil }
        return KeystoreCredentials(
            keystorePath: keystoreURL.path, storePassword: storePassword,
            keyAlias: keyAlias.isEmpty ? nil : keyAlias,
            keyPassword: keyPassword.isEmpty ? nil : keyPassword)
    }

    /// One line for a collapsed summary row ("how will this be signed?").
    var summary: String {
        switch mode {
        case .debug: return "Debug keystore"
        case .existing: return keystoreURL?.lastPathComponent ?? "No keystore selected"
        case .create: return "New keystore (not created yet)"
        }
    }

    /// The full field state, for cancel-safe editing in a sheet.
    struct Snapshot {
        let mode: Mode
        let keystoreURL: URL?
        let storePassword: String
        let keyAlias: String
        let keyPassword: String
        let newKeystoreURL: URL?
        let newCommonName: String
        let newOrganization: String
    }

    func snapshot() -> Snapshot {
        Snapshot(
            mode: mode, keystoreURL: keystoreURL, storePassword: storePassword,
            keyAlias: keyAlias, keyPassword: keyPassword, newKeystoreURL: newKeystoreURL,
            newCommonName: newCommonName, newOrganization: newOrganization)
    }

    func restore(_ snapshot: Snapshot) {
        mode = snapshot.mode
        keystoreURL = snapshot.keystoreURL
        storePassword = snapshot.storePassword
        keyAlias = snapshot.keyAlias
        keyPassword = snapshot.keyPassword
        newKeystoreURL = snapshot.newKeystoreURL
        newCommonName = snapshot.newCommonName
        newOrganization = snapshot.newOrganization
        createError = nil
    }

    func chooseKeystore() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a keystore (.jks / .keystore)"
        if panel.runModal() == .OK { keystoreURL = panel.url }
    }

    func chooseNewKeystoreLocation() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(keyAlias.isEmpty ? "release" : keyAlias).jks"
        panel.canCreateDirectories = true
        panel.directoryURL = try? ScreenCaptureService.ensureCaptureDir()
        if panel.runModal() == .OK { newKeystoreURL = panel.url }
    }

    /// Create the keystore with keytool, then select it for signing
    /// (mode flips to `.existing` with the passwords/alias already filled in).
    func createKeystore(using state: AppState) {
        guard let newKeystoreURL else { return }
        let spec = NewKeystore(
            path: newKeystoreURL.path, alias: keyAlias, storePassword: storePassword,
            keyPassword: keyPassword.isEmpty ? nil : keyPassword,
            commonName: newCommonName, organization: newOrganization.isEmpty ? nil : newOrganization)
        creating = true
        createError = nil
        Task {
            do {
                _ = try await state.env.engine.apkSigning.createKeystore(spec)
                keystoreURL = newKeystoreURL
                mode = .existing
                state.showToast(Toast(
                    message: "Created \(newKeystoreURL.lastPathComponent)",
                    ok: true, revealPath: newKeystoreURL.path))
            } catch {
                createError = error.localizedDescription
            }
            creating = false
        }
    }
}

/// The mode picker + per-mode fields, dropped into a `Form` section by both
/// the APK signer and the AAB converter's signing sheet.
struct SigningKeyFields: View {
    @Environment(AppState.self) private var state
    @Bindable var model: SigningKeyModel

    var body: some View {
        Picker("Key", selection: $model.mode) {
            ForEach(SigningKeyModel.Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.radioGroup)
        switch model.mode {
        case .debug: debugKeyNote
        case .existing: keystoreFields
        case .create: createFields
        }
    }

    @ViewBuilder private var debugKeyNote: some View {
        if !model.debugKeystoreExists {
            Label(
                "No debug keystore at ~/.android/debug.keystore yet — build any app once, or use your own keystore.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.app(.caption)).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var keystoreFields: some View {
        LabeledContent("Keystore") {
            HStack {
                Text(model.keystoreURL?.lastPathComponent ?? "None").foregroundStyle(.textMuted)
                Button("Choose…") { model.chooseKeystore() }
            }
        }
        SecureField("Store password", text: $model.storePassword)
        TextField("Key alias (optional)", text: $model.keyAlias)
        SecureField("Key password (optional — defaults to store password)", text: $model.keyPassword)
    }

    @ViewBuilder private var createFields: some View {
        LabeledContent("Save as") {
            HStack {
                Text(model.newKeystoreURL?.lastPathComponent ?? "Choose a location…")
                    .foregroundStyle(.textMuted)
                Button("Choose…") { model.chooseNewKeystoreLocation() }
            }
        }
        TextField("Key alias", text: $model.keyAlias)
        TextField("Common name (CN)", text: $model.newCommonName)
        TextField("Organization (optional)", text: $model.newOrganization)
        SecureField("Store password", text: $model.storePassword)
        SecureField("Key password (optional — defaults to store password)", text: $model.keyPassword)
        Button(model.creating ? "Creating…" : "Create keystore") { model.createKeystore(using: state) }
            .disabled(!model.canCreate)
        if let createError = model.createError {
            Label(createError, systemImage: "xmark.octagon.fill")
                .font(.app(.caption)).foregroundStyle(.red)
        }
        Text("Creates a self-signed RSA-2048 keystore (valid ~27 years) and selects it for signing.")
            .font(.app(.caption)).foregroundStyle(.textMuted)
    }
}

/// The signing-key picker as a compact sheet that hugs its content — no
/// scrolling in any mode. Field labels ride the placeholders to keep the
/// height down; Done is gated on a complete choice.
struct SigningKeySheet: View {
    @Environment(AppState.self) private var state
    @Bindable var model: SigningKeyModel
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signing key")
                .font(.app(.title3).weight(.semibold))
            Picker("", selection: $model.mode) {
                ForEach(SigningKeyModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            switch model.mode {
            case .debug: debugNote
            case .existing: keystoreFields
            case .create: createFields
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isComplete)
            }
        }
        .padding(18)
        .frame(width: 440)
        .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder private var debugNote: some View {
        if model.debugKeystoreExists {
            Text("Signs with ~/.android/debug.keystore — all a device install needs.")
                .font(.app(.caption)).foregroundStyle(.textMuted)
        } else {
            Label(
                "No debug keystore at ~/.android/debug.keystore yet — build any app once, or use your own keystore.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.app(.caption)).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var keystoreFields: some View {
        fileRow(
            model.keystoreURL?.lastPathComponent ?? "No keystore selected",
            picked: model.keystoreURL != nil
        ) { model.chooseKeystore() }
        SecureField("Store password", text: $model.storePassword, prompt: Text("Store password (required)"))
        TextField("Key alias", text: $model.keyAlias, prompt: Text("Key alias — optional"))
        SecureField(
            "Key password", text: $model.keyPassword,
            prompt: Text("Key password — optional, defaults to store password"))
    }

    @ViewBuilder private var createFields: some View {
        fileRow(
            model.newKeystoreURL?.lastPathComponent ?? "Where to save the keystore…",
            picked: model.newKeystoreURL != nil
        ) { model.chooseNewKeystoreLocation() }
        TextField("Key alias", text: $model.keyAlias, prompt: Text("Key alias"))
        TextField("Common name", text: $model.newCommonName, prompt: Text("Common name (CN)"))
        TextField("Organization", text: $model.newOrganization, prompt: Text("Organization — optional"))
        SecureField("Store password", text: $model.storePassword, prompt: Text("Store password"))
        SecureField(
            "Key password", text: $model.keyPassword,
            prompt: Text("Key password — optional, defaults to store password"))
        HStack(spacing: 10) {
            Button(model.creating ? "Creating…" : "Create keystore") { model.createKeystore(using: state) }
                .disabled(!model.canCreate)
            Text("Self-signed RSA-2048, valid ~27 years — selected for signing once created.")
                .font(.app(.caption)).foregroundStyle(.textMuted)
        }
        if let createError = model.createError {
            Label(createError, systemImage: "xmark.octagon.fill")
                .font(.app(.caption)).foregroundStyle(.red)
        }
    }

    private func fileRow(_ label: String, picked: Bool, choose: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.app(.callout))
                .foregroundStyle(picked ? AnyShapeStyle(.primary) : AnyShapeStyle(.textMuted))
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose…", action: choose)
            Spacer()
        }
    }
}
