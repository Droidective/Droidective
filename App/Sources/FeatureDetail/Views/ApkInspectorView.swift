import ADBKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Inspect a local `.apk` without installing it — manifest identity, permissions,
/// features, the debuggable flag, and signing certificates. Drag an APK onto the
/// drop zone or pick a file; details are read with the SDK's aapt2 (and apksigner
/// for certificates). No device required.
struct ApkInspectorView: View {
    @Environment(AppState.self) private var state
    @State private var apkURL: URL?
    @State private var report: ApkReport?
    @State private var loading = false
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if let report {
                reportScroll(report)
            } else {
                dropZone
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: apkURL) { await load() }
    }

    private func load() async {
        guard let apkURL else { return }
        loading = true
        defer { loading = false }
        let result = await state.env.engine.apkInspection.inspect(apkPath: apkURL.path)
        guard !Task.isCancelled else { return }
        report = result
    }

    private func stage(_ url: URL) {
        report = nil
        apkURL = url
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { stage(url) }
    }

    // MARK: - Empty state

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 46))
                .foregroundStyle(.brandAccent)
            Text(loading ? "Inspecting…" : "Drag an APK here to inspect")
                .font(.title3.weight(.medium))
            Button("Choose APK…") { choose() }
                .disabled(loading)
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

    // MARK: - Report

    private func reportScroll(_ report: ApkReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(report)
                if !report.permissions.isEmpty {
                    listSection("Permissions", systemImage: "lock.shield", items: report.permissions)
                }
                if !report.features.isEmpty {
                    listSection("Features", systemImage: "puzzlepiece.extension", items: report.features)
                }
                signingSection(report)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ report: ApkReport) -> some View {
        let info = report.info
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.label ?? info.fileName)
                        .font(.title2.weight(.semibold))
                    if let package = info.packageName {
                        Text(package).font(.callout).foregroundStyle(.textMuted).textSelection(.enabled)
                    }
                }
                Spacer()
                Button("Inspect another…") { choose() }
            }
            FlowChips {
                if let version = info.versionName {
                    chip("v\(version)" + (info.versionCode.map { " (\($0))" } ?? ""))
                }
                if let min = info.minSdk { chip("min SDK \(min)") }
                if let target = info.targetSdk { chip("target SDK \(target)") }
                chip(ByteCountFormatter.string(fromByteCount: Int64(info.fileSizeBytes), countStyle: .file))
                if report.isDebuggable { badge("Debuggable", color: .orange) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func listSection(_ title: String, systemImage: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(title) (\(items.count))", systemImage: systemImage).font(.headline)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.callout.monospaced())
                    .foregroundStyle(.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private func signingSection(_ report: ApkReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Signing", systemImage: "checkmark.seal").font(.headline)
            if report.signers.isEmpty && report.signatureSchemes.isEmpty {
                Text("Signing details need the Android SDK's apksigner and a Java runtime.")
                    .font(.callout).foregroundStyle(.textMuted)
            } else {
                if !report.signatureSchemes.isEmpty {
                    FlowChips { ForEach(report.signatureSchemes, id: \.self) { chip($0.uppercased()) } }
                }
                ForEach(Array(report.signers.enumerated()), id: \.offset) { _, signer in
                    VStack(alignment: .leading, spacing: 2) {
                        if let dn = signer.subjectDN {
                            Text(dn).font(.callout).textSelection(.enabled)
                        }
                        if let sha = signer.sha256 {
                            Text("SHA-256: \(sha)")
                                .font(.caption.monospaced()).foregroundStyle(.textMuted).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Wraps chips onto new lines when they overflow the available width.
private struct FlowChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
