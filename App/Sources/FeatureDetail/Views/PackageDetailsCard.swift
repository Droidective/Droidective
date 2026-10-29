import ADBKit
import SwiftUI

/// What an app package is, for the screens that install one: the app's name
/// and package, its version, the Android versions it needs and targets, what
/// the file holds, its native code, launcher, signer and permissions — then
/// the live install status, then whatever `actions` the screen adds.
///
/// Read by `PackageDetailsService`, which reads a bundle through its base APK,
/// so all four formats say the same things. Without the SDK build-tools it is
/// thinner, and says why rather than leaving rows out unexplained.
struct PackageDetailsCard<Actions: View>: View {
    @Environment(AppState.self) private var state
    let url: URL
    private let actions: Actions

    @State private var details: PackageDetails?
    @State private var loading = true
    @State private var hasAapt2 = true
    @State private var showsPermissions = false

    init(url: URL, @ViewBuilder actions: () -> Actions) {
        self.url = url
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the package…")
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                }
            } else if let details {
                facts(details)
            }
            InstallJobRows(urls: [url])
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.borderSubtle, lineWidth: 1)
        }
        .task(id: url) { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.app(size: 30))
                .foregroundStyle(.brandAccent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(details?.label ?? url.lastPathComponent)
                        .font(.app(.title3).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if details?.report?.isDebuggable == true {
                        Text("Debuggable")
                            .font(.app(.caption2).weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .help("Built debuggable — a debug build, or a release build with debugging left on")
                    }
                }
                if let package = details?.packageName {
                    Text(package)
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Facts

    @ViewBuilder private func facts(_ details: PackageDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                if let version = details.versionSummary { row("Version", version) }
                if let requires = details.requiresSummary { row("Requires", requires) }
                if let targets = details.targetsSummary { row("Targets", targets) }
                row("File", "\(details.fileName) · \(Self.size(details.fileSizeBytes))")
                if let contents = details.contentsSummary { row("Contains", contents) }
                if let nativeCode = details.nativeCodeSummary { row("Native code", nativeCode) }
                if let launcher = details.launcherSummary {
                    row("Opens", launcher, tint: details.hasNoLauncher ? .orange : nil)
                }
                if let signer = details.signerSummary { row("Signed by", signer) }
            }
            if !details.permissionNames.isEmpty { permissionList(details.permissionNames) }
            if let note = details.missingNote(hasAapt2: hasAapt2) {
                Text(note)
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        GridRow {
            Text(label)
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
                .gridColumnAlignment(.leading)
            Text(value)
                .font(.app(.callout))
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func permissionList(_ permissions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                showsPermissions.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showsPermissions ? "chevron.down" : "chevron.right")
                        .font(.app(.caption2).weight(.semibold))
                    Text("\(permissions.count) permission\(permissions.count == 1 ? "" : "s")")
                        .font(.app(.caption))
                }
                .foregroundStyle(.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsPermissions {
                Text(permissions.joined(separator: "\n"))
                    .font(.app(.caption).monospaced())
                    .textSelection(.enabled)
                    .padding(.leading, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Formatting

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Loading

    private func load() async {
        loading = true
        let engine = state.env.engine
        let read = await engine.packageDetails.details(packagePath: url.path)
        let tools = await engine.toolchain.aapt2() != nil
        guard !Task.isCancelled else { return }
        details = read
        hasAapt2 = tools
        loading = false
    }
}

extension PackageDetailsCard where Actions == EmptyView {
    init(url: URL) {
        self.init(url: url) { EmptyView() }
    }
}
