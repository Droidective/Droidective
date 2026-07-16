import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Live conversion stage, mirrored from the service's `@Sendable` callback
/// (a `@MainActor` class so the closure can carry it across the hop).
@MainActor @Observable
private final class ConvertStage {
    var text: String?
}

/// Convert an Android App Bundle (`.aab`) into an installable universal APK
/// with the managed bundletool: tool gate → pick/drop a bundle → convert with
/// a live stage line → result card (Install / Save a Copy / Reveal / Studio).
/// Double-clicking an `.aab` in Finder lands here with the bundle staged.
struct AabConvertView: View {
    @Environment(AppState.self) private var state
    @State private var missingBundletool = false
    @State private var missingJava = false
    @State private var checkingTool = true

    private var toolReady: Bool { !missingBundletool && !missingJava }
    @State private var download = DownloadState()
    @State private var setupError: String?
    @State private var aabURL: URL?
    @State private var dropTargeted = false
    @State private var converting = false
    @State private var stage = ConvertStage()
    @State private var converted: AabConvertService.ConvertedApk?
    @State private var convertError: String?
    @State private var keystoreExpanded = false
    @State private var keystoreURL: URL?
    @State private var storePassword = ""
    @State private var keyAlias = ""
    @State private var keyPassword = ""

    private var targets: [Device] {
        state.devices.filter { state.targetSerials.contains($0.serial) }
    }

    var body: some View {
        Group {
            if checkingTool {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !toolReady {
                setupGate
            } else if let converted {
                resultCard(converted)
            } else if converting {
                convertingStatus
            } else if aabURL != nil {
                stagedCard
            } else {
                aabPicker
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await checkTools()
            consumePending()
        }
        .onChange(of: state.pendingConvertAAB) { _, _ in consumePending() }
    }

    /// An `.aab` double-clicked in Finder arrives here; a new one replaces the
    /// current selection (and any previous result) rather than being dropped.
    private func consumePending() {
        guard let pending = state.pendingConvertAAB else { return }
        state.pendingConvertAAB = nil
        guard !converting else {
            state.showToast(Toast(
                message: "A conversion is running — reopen \(pending.lastPathComponent) once it finishes",
                ok: false))
            return
        }
        converted = nil
        convertError = nil
        aabURL = pending
    }

    // MARK: - Setup gate

    /// bundletool ships inside the app (seeded into the managed store at
    /// launch), so this gate is normally about a missing Java runtime only —
    /// the bundletool row appears just when the seeded copy was deleted.
    private var setupGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox").font(.app(size: 46)).foregroundStyle(.brandAccent)
            Text(missingJava ? "Set up a Java runtime" : "Set up bundletool")
                .font(.app(.title2).weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                if missingBundletool {
                    setupRow("bundletool", detail: "Google's App Bundle tool — downloaded from GitHub releases, kept up to date.")
                }
                if missingJava {
                    setupRow("Java runtime", detail: "Used to run bundletool. A detected JDK is reused; otherwise Temurin is fetched.")
                }
            }
            .frame(maxWidth: 460)
            if download.active {
                downloadProgress
            } else if let setupError {
                Text(setupError)
                    .font(.app(.callout))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            Button(download.active
                ? "Downloading…"
                : "Download \(missingJava ? "a Java runtime" : "bundletool") & continue"
            ) {
                Task { await setUpTools() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(download.active)
            Text("Manage versions anytime in Settings ▸ Tools.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func setupRow(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.circle").foregroundStyle(.brandAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.callout).weight(.medium))
                Text(detail).font(.app(.caption)).foregroundStyle(.textMuted)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var downloadProgress: some View {
        Group {
            if let fraction = download.fraction {
                ProgressView(value: fraction) { Text(download.label ?? "Downloading…") }
            } else {
                ProgressView { Text(download.label ?? "Downloading…") }
            }
        }
        .frame(maxWidth: 360)
    }

    // MARK: - Picker / staged bundle

    private var aabPicker: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.app(size: 46))
                .foregroundStyle(.brandAccent)
            Text("Drag an App Bundle here")
                .font(.app(.title3).weight(.medium))
            Text("Or double-click an .aab in Finder — it opens on this screen.")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
            Button("Choose AAB…") { choose() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    dropTargeted ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.borderSubtle),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [7])
                )
                .padding(20)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let aab = urls.first(where: { $0.pathExtension.lowercased() == "aab" }) else { return false }
            converted = nil
            convertError = nil
            aabURL = aab
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var stagedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.app(size: 46))
                .foregroundStyle(.brandAccent)
            VStack(spacing: 2) {
                Text(aabURL?.lastPathComponent ?? "")
                    .font(.app(.title3).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileSize(aabURL))
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }
            if let convertError {
                Text(convertError)
                    .font(.app(.callout))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 460)
            }
            signingSection
            HStack(spacing: 10) {
                Button("Clear") {
                    aabURL = nil
                    convertError = nil
                }
                Button("Convert to APK") { Task { await convert() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(needsStorePassword)
            }
            Text(signingCaption)
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.brandAccent, lineWidth: 2)
        }
    }

    /// Optional release-keystore fields, collapsed by default — without them
    /// bundletool signs with the debug keystore, which is all a device install
    /// needs. A picked keystore requires its password before Convert enables.
    private var signingSection: some View {
        DisclosureGroup(isExpanded: $keystoreExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(keystoreURL?.lastPathComponent ?? "No keystore selected")
                        .font(.app(.callout))
                        .foregroundStyle(keystoreURL == nil ? AnyShapeStyle(.textMuted) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { chooseKeystore() }
                    if keystoreURL != nil {
                        Button("Remove") {
                            keystoreURL = nil
                            storePassword = ""
                            keyAlias = ""
                            keyPassword = ""
                        }
                    }
                    Spacer()
                }
                if keystoreURL != nil {
                    SecureField("Keystore password (required)", text: $storePassword)
                        .textFieldStyle(.roundedBorder)
                    TextField("Key alias — optional, for multi-key keystores", text: $keyAlias)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Key password — optional, defaults to the keystore password", text: $keyPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Sign with a release keystore — optional", systemImage: "signature")
                .font(.app(.callout))
        }
        .frame(maxWidth: 420)
        .padding(.top, 4)
    }

    private var needsStorePassword: Bool {
        keystoreURL != nil && storePassword.isEmpty
    }

    private var signingCaption: String {
        if needsStorePassword {
            return "Enter the keystore password to convert."
        }
        if let keystoreURL {
            return "Builds a universal APK signed with \(keystoreURL.lastPathComponent)."
        }
        return "Builds a universal APK with bundletool — installable on any device."
    }

    private func chooseKeystore() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a keystore (.jks / .keystore)"
        if panel.runModal() == .OK, let url = panel.url { keystoreURL = url }
    }

    private var convertingStatus: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(stage.text ?? "Converting…")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
            Text(aabURL?.lastPathComponent ?? "")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result

    private func resultCard(_ result: AabConvertService.ConvertedApk) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.app(size: 46))
                .foregroundStyle(.green)
            VStack(spacing: 2) {
                Text(result.url.lastPathComponent)
                    .font(.app(.title3).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: result.sizeBytes, countStyle: .file))
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }
            InstallJobRows(urls: [result.url])
                .frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button("Install on device") { install(result) }
                    .buttonStyle(.borderedProminent)
                    .disabled(targets.isEmpty || installRunning(result))
                Button("Save a Copy…") { saveCopy(result) }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([result.url])
                }
            }
            if targets.isEmpty {
                Label("Connect a device to install onto", systemImage: "iphone.slash")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }
            Button("Convert another bundle") {
                aabURL = nil
                converted = nil
                convertError = nil
            }
            .buttonStyle(.link)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.borderSubtle, lineWidth: 1)
        }
    }

    // MARK: - Actions

    private func checkTools() async {
        checkingTool = true
        // Re-seed first: the launch seed is async and a Settings ▸ Tools delete
        // may have removed the jar — this makes the gate independent of both.
        await BundledTools.seed(into: state.env.engine.managedTools)
        missingBundletool = await state.env.engine.managedTools.resolve(.bundletool) == nil
        missingJava = await state.env.engine.toolchain.java() == nil
        checkingTool = false
    }

    private func setUpTools() async {
        do {
            if missingJava {
                try await installTool(.temurinJre, arch: ManagedToolStore.macArch, label: "Java runtime")
                missingJava = false
            }
            if missingBundletool {
                try await installTool(.bundletool, arch: "", label: "bundletool")
                missingBundletool = false
            }
            setupError = nil
        } catch {
            setupError = "Setup failed: \(error.localizedDescription)"
        }
        download.finish()
    }

    private func installTool(_ tool: ManagedTool, arch: String, label: String) async throws {
        let progress = download
        progress.begin("Downloading \(label)…")
        let onProgress: @Sendable (Double) -> Void = { value in Task { @MainActor in progress.update(value) } }
        let path = try await state.env.engine.managedTools.install(tool, arch: arch, onProgress: onProgress)
        let version = await state.env.engine.managedTools.installedVersion(tool) ?? ""
        state.showToast(Toast(
            message: "Downloaded \(label) \(version)".trimmingCharacters(in: .whitespaces),
            ok: true, copyText: path, revealPath: path))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "aab") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            converted = nil
            convertError = nil
            aabURL = url
        }
    }

    private func convert() async {
        guard let aabURL else { return }
        converting = true
        convertError = nil
        defer { converting = false }
        let stage = stage
        stage.text = "Building APKs with bundletool…"
        let credentials = keystoreURL.map {
            KeystoreCredentials(
                keystorePath: $0.path, storePassword: storePassword,
                keyAlias: keyAlias.isEmpty ? nil : keyAlias,
                keyPassword: keyPassword.isEmpty ? nil : keyPassword)
        }
        do {
            let outDir = try ScreenCaptureService.ensureCaptureDir()
            let result = try await state.withOperation("Converting \(aabURL.lastPathComponent) to APK…") {
                try await state.env.engine.aabConvert.convert(
                    aabPath: aabURL.path, outputDirectory: outDir, credentials: credentials
                ) { step in
                    Task { @MainActor in
                        stage.text = step == .buildingApks
                            ? "Building APKs with bundletool…"
                            : "Extracting universal.apk…"
                    }
                }
            }
            guard !Task.isCancelled else { return }
            converted = result
            state.showToast(Toast(
                message: "Converted to \(result.url.lastPathComponent)",
                ok: true, revealPath: result.url.path))
        } catch {
            guard !Task.isCancelled else { return }
            convertError = error.localizedDescription
        }
    }

    private func installRunning(_ result: AabConvertService.ConvertedApk) -> Bool {
        state.installJobs.contains { $0.apkURL == result.url && $0.isRunning }
    }

    private func install(_ result: AabConvertService.ConvertedApk) {
        let serials = targets.map(\.serial)
        guard !serials.isEmpty else { return }
        state.startInstall([result.url], onSerials: serials)
    }

    private func saveCopy(_ result: AabConvertService.ConvertedApk) {
        guard let destination = state.askSaveLocation(suggestedName: result.url.lastPathComponent) else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: result.url, to: destination)
            state.showToast(Toast(
                message: "Saved \(destination.lastPathComponent)", ok: true, revealPath: destination.path))
        } catch {
            state.showToast(Toast(message: "Couldn't save: \(error.localizedDescription)", ok: false))
        }
    }

    private func fileSize(_ url: URL?) -> String {
        guard let url,
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        else { return "" }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }
}
