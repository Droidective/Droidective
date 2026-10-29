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
                if details.versionName != nil || details.versionCode != nil {
                    row("Version", InstallPlan.versionLabel(name: details.versionName, code: details.versionCode))
                }
                if let minSdk = details.report?.info.minSdk {
                    row("Requires", "\(AndroidRelease.describe(apiLevel: minSdk)) or later")
                }
                if let targetSdk = details.report?.info.targetSdk {
                    row("Targets", AndroidRelease.describe(apiLevel: targetSdk))
                }
                row("File", "\(details.fileName) · \(Self.size(details.fileSizeBytes))")
                if let contents = Self.contents(details) { row("Contains", contents) }
                if let nativeCode = Self.nativeCode(details) { row("Native code", nativeCode) }
                if details.hasBadging { launcherRow(details.report?.launchableActivity) }
                if let signer = details.report?.signers.first {
                    row("Signed by", Self.signature(signer, schemes: details.report?.signatureSchemes ?? []))
                }
            }
            if let permissions = details.report?.permissions, !permissions.isEmpty {
                permissionList(permissions)
            }
            if let note = missingNote(details) {
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

    /// Which activity "open" starts — or that there is none, which is why
    /// opening it after installing would fail.
    private func launcherRow(_ activity: String?) -> some View {
        guard let activity else {
            return row("Opens", "No launcher activity — nothing to open", tint: .orange)
        }
        return row("Opens", activity.split(separator: ".").last.map(String.init) ?? activity)
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
                Text(permissions.map(Self.shortPermission).joined(separator: "\n"))
                    .font(.app(.caption).monospaced())
                    .textSelection(.enabled)
                    .padding(.leading, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func missingNote(_ details: PackageDetails) -> String? {
        guard !details.hasBadging else { return nil }
        if !hasAapt2 {
            return "The SDK levels, permissions and native code need the Android SDK build-tools (aapt2)."
        }
        if details.format != .apk, details.report == nil {
            return "Couldn't find the app's base APK inside this \(details.format.displayName)."
        }
        return "aapt2 couldn't read this package — it may be damaged."
    }

    // MARK: - Formatting

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func contents(_ details: PackageDetails) -> String? {
        guard details.format != .apk, details.apkCount > 0 else { return nil }
        var parts = ["\(details.apkCount) APK\(details.apkCount == 1 ? "" : "s")"]
        if details.expansionCount > 0 {
            parts.append("\(details.expansionCount) expansion file\(details.expansionCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    private static func nativeCode(_ details: PackageDetails) -> String? {
        if !details.abis.isEmpty { return details.abis.joined(separator: ", ") }
        return details.hasBadging ? "None — runs on any CPU" : nil
    }

    private static func signature(_ signer: ApkSigner, schemes: [String]) -> String {
        let name = signer.commonName ?? "Unknown signer"
        guard !schemes.isEmpty else { return name }
        return "\(name) · \(schemes.joined(separator: ", ")) scheme\(schemes.count == 1 ? "" : "s")"
    }

    private static func shortPermission(_ permission: String) -> String {
        let prefix = "android.permission."
        return permission.hasPrefix(prefix) ? String(permission.dropFirst(prefix.count)) : permission
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
