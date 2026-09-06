import ADBKit
import SwiftUI

/// The prompt a package drop stops at.
///
/// Installing replaces an app someone may be mid-way through using, and a
/// downgrade or a signature change can only be done by wiping its data — so
/// the drop announces, and then this asks. It reads the APK (aapt2, when the
/// SDK build-tools are there) and the device (dumpsys) and states the version
/// it is moving *from* and *to*, because that is the fact the decision turns
/// on. With no build-tools it still appears, thinner: a prompt that vanishes
/// on some machines is worse than one that occasionally can't show a version.
struct InstallDropSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let request: PendingInstallDrop

    @State private var infos: [String: ApkInfo] = [:]
    @State private var installed: [String: InstalledAppVersion] = [:]
    @State private var loaded = false
    @State private var replace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if request.paths.count == 1 {
                    versionRows(for: request.paths[0])
                } else {
                    packageRows
                }
                if loaded, offersChoice { choice }
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 440)
        .background(.bgSurface)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.app(size: 30))
                .foregroundStyle(.brandAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.title3).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        guard request.paths.count == 1 else { return "\(request.paths.count) app packages" }
        let info = infos[request.paths[0]]
        return info?.label ?? URL(fileURLWithPath: request.paths[0]).lastPathComponent
    }

    private var subtitle: String {
        var parts: [String] = []
        if request.paths.count == 1, let info = infos[request.paths[0]] {
            if let package = info.packageName { parts.append(package) }
            if info.fileSizeBytes > 0 { parts.append(Self.size(info.fileSizeBytes)) }
        }
        parts.append(request.deviceName)
        return parts.joined(separator: " · ")
    }

    // MARK: - Versions

    @ViewBuilder private func versionRows(for path: String) -> some View {
        let local = infos[path]
        let device = installedVersion(for: path)
        VStack(spacing: 0) {
            versionRow(
                label: "On device",
                value: device.map { InstallPlan.versionLabel(name: $0.versionName, code: $0.versionCode) }
                    ?? (loaded ? "Not installed" : "…"),
                flag: nil)
            Divider()
            versionRow(
                label: "Dropped",
                value: loaded
                    ? InstallPlan.versionLabel(name: local?.versionName, code: local?.versionCode)
                    : "…",
                flag: relationFlag(decision(for: path)))
        }
        .background(.bgRoot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.borderSubtle, lineWidth: 1)
        }
    }

    private func versionRow(label: String, value: String, flag: String?) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.app(.callout).monospacedDigit())
            Spacer(minLength: 0)
            if let flag {
                Text(flag)
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    private func relationFlag(_ decision: InstallDecision) -> String? {
        switch decision.relation {
        case .downgrade: "older"
        case .reinstall: "same version"
        case .update, .notInstalled, .unknown: nil
        }
    }

    private var packageRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(request.paths.enumerated()), id: \.offset) { index, path in
                if index > 0 { Divider() }
                HStack(spacing: 10) {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.app(.callout))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if loaded {
                        Text(relationLabel(decision(for: path)))
                            .font(.app(.caption))
                            .foregroundStyle(
                                decision(for: path).relation == .downgrade ? Color.orange : .textMuted)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
            }
        }
        .background(.bgRoot, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.borderSubtle, lineWidth: 1)
        }
    }

    private func relationLabel(_ decision: InstallDecision) -> String {
        switch decision.relation {
        case .notInstalled: "New"
        case .update: "Update"
        case .reinstall: "Reinstall"
        case .downgrade: "Downgrade"
        case .unknown: "Install"
        }
    }

    // MARK: - Keep or replace

    private var choice: some View {
        VStack(alignment: .leading, spacing: 10) {
            choiceRow(
                selected: !replace, enabled: canKeepData,
                title: "Keep app data",
                note: keepDataNote ?? "Reinstalls over the installed copy") { replace = false }
            choiceRow(
                selected: replace, enabled: true,
                title: "Replace",
                note: "Uninstalls first · clears app data") { replace = true }
        }
    }

    private func choiceRow(
        selected: Bool, enabled: Bool, title: String, note: String, select: @escaping () -> Void
    ) -> some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.app(.callout))
                    .foregroundStyle(selected ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.textMuted))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(.callout))
                    Text(note).font(.app(.caption)).foregroundStyle(.textMuted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            // The alternative the drop overlay promised: a build you want to
            // hand to someone, not run.
            Button("Copy to \(request.destination)") { copyInstead() }
            Spacer(minLength: 0)
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(primaryTitle) { install() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!loaded)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bgRoot)
    }

    // MARK: - Decisions

    private func decision(for path: String) -> InstallDecision {
        InstallPlan.decide(
            local: infos[path] ?? ApkInfo(
                fileName: URL(fileURLWithPath: path).lastPathComponent, fileSizeBytes: 0),
            installed: installedVersion(for: path))
    }

    private func installedVersion(for path: String) -> InstalledAppVersion? {
        guard let package = infos[path]?.packageName else { return nil }
        return installed[package]
    }

    private var decisions: [InstallDecision] { request.paths.map(decision(for:)) }

    private var canKeepData: Bool { decisions.allSatisfy(\.canKeepData) }

    private var offersChoice: Bool { decisions.contains { $0.offersChoice } }

    private var keepDataNote: String? {
        if canKeepData { return decisions.compactMap(\.keepDataNote).first }
        return request.paths.count == 1
            ? decisions[0].keepDataNote
            : "One of these is a downgrade"
    }

    private var primaryTitle: String {
        guard loaded else { return "Install" }
        guard request.paths.count == 1 else { return "Install \(request.paths.count) apps" }
        return decisions[0].primaryTitle
    }

    // MARK: - Actions

    private func install() {
        for path in request.paths {
            state.installDropped(
                [path], serial: request.serial,
                packageID: infos[path]?.packageName,
                replacingFirst: replace)
        }
        dismiss()
    }

    private func copyInstead() {
        state.copyToDevice(request.paths, toDir: request.destination, serial: request.serial)
        dismiss()
    }

    // MARK: - Loading

    private func load() async {
        let engine = state.env.engine
        var readInfos: [String: ApkInfo] = [:]
        for path in request.paths {
            readInfos[path] = await engine.appInstall.inspect(apkPath: path)
        }
        guard !Task.isCancelled else { return }
        infos = readInfos

        var readInstalled: [String: InstalledAppVersion] = [:]
        for package in Set(readInfos.values.compactMap(\.packageName)) {
            guard let info = try? await engine.inspection.getAppInfo(
                serial: request.serial, packageId: package), info.installed else { continue }
            readInstalled[package] = InstalledAppVersion(
                versionName: info.versionName, versionCode: info.versionCode)
        }
        guard !Task.isCancelled else { return }
        installed = readInstalled
        loaded = true
        replace = decisions.contains { $0.replaceByDefault }
    }

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
