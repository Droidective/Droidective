import ADBKit
import AppKit
import SwiftUI

struct ApiResponsePane: View {
    let model: ApiClientModel
    @Binding var alertMessage: String?
    let compact: Bool

    private enum Tab: String, CaseIterable, Identifiable {
        case body
        case headers
        case cookies
        case timing

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @State private var tab: Tab = .body
    @State private var showRaw = false
    @AppStorage("apiBodyWraps") private var wraps = true
    @State private var findToken = 0

    var body: some View {
        VStack(spacing: 0) {
            if let response = model.response {
                statusBar(response)
                Divider()
                if !model.assertionResults.isEmpty { assertionStrip }
                content(response)
            } else if let error = model.errorText {
                errorState(error)
            } else if model.isSending {
                ProgressView("Sending…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .background(.bgSurface.opacity(0.3))
    }

    // MARK: - Status

    private func statusBar(_ response: ApiResponse) -> some View {
        HStack(spacing: 10) {
            Text("\(response.statusCode)")
                .font(.app(.headline, design: .monospaced))
                .foregroundStyle(ApiStatusStyle.color(for: response.statusCode))
            if !compact {
                Text(response.statusText)
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }
            Text(String(format: "%.0f ms", response.elapsedMs))
                .font(.app(.caption, design: .monospaced))
                .foregroundStyle(.textMuted)
            Text(response.sizeText)
                .font(.app(.caption, design: .monospaced))
                .foregroundStyle(.textMuted)
            if response.truncated {
                Text("truncated")
                    .font(.app(.caption2))
                    .foregroundStyle(.orange)
                    .help("The body was larger than the per-request limit in Settings.")
            }

            Menu {
                Button("Save Body to File…") { saveBody(response) }
                Divider()
                Button("Copy Everything") { copy(everythingText(response)) }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Takes the width left over from the status metrics and sits against
            // the trailing edge, dropping tabs into a menu only once they truly
            // stop fitting.
            AdaptiveTabBar(
                tabs: Tab.allCases, label: \.label, selection: $tab, alignment: .trailing
            )
        }
        .padding(8)
    }

    /// One clipboard-friendly dump of the whole exchange, for pasting into an
    /// issue: status line, headers, then the body as shown.
    private func everythingText(_ response: ApiResponse) -> String {
        var parts = [
            "\(response.statusCode) \(response.statusText) · "
                + String(format: "%.0f ms", response.elapsedMs) + " · \(response.sizeText)"
        ]
        if !response.finalURL.isEmpty { parts.append(response.finalURL) }
        let headers = headerText(response)
        if !headers.isEmpty { parts.append(headers) }
        let body = bodyText(response)
        if !body.isEmpty { parts.append(body) }
        return parts.joined(separator: "\n\n")
    }

    /// The copy button every section carries, so the thing on screen is always
    /// one click from the clipboard.
    private func copyButton(_ help: String, _ text: @escaping () -> String) -> some View {
        Button { copy(text()) } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.borderless)
            .help(help)
    }

    /// A section's own header strip: a title, its copy button, and whatever else
    /// that section needs on the right.
    private func sectionBar(
        _ title: String, copyHelp: String, copying text: @escaping () -> String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            copyButton(copyHelp, text)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var assertionStrip: some View {
        let summary = ApiAssertions.summary(model.assertionResults)
        return HStack(spacing: 8) {
            Image(systemName: summary.failed == 0 ? "checkmark.seal.fill" : "xmark.seal.fill")
                .foregroundStyle(summary.failed == 0 ? .green : .red)
            Text("\(summary.passed) passed · \(summary.failed) failed")
                .font(.app(.caption))
            Spacer()
            if summary.failed > 0,
               let first = model.assertionResults.first(where: { !$0.passed }) {
                Text(first.label)
                    .font(.app(.caption2))
                    .foregroundStyle(.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((summary.failed == 0 ? Color.green : Color.red).opacity(0.08))
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ response: ApiResponse) -> some View {
        switch tab {
        case .body: bodyTab(response)
        case .headers: headersTab(response)
        case .cookies: cookiesTab(response)
        case .timing: timingTab(response)
        }
    }

    @ViewBuilder
    private func bodyTab(_ response: ApiResponse) -> some View {
        VStack(spacing: 0) {
            bodyToolbar(response)
            bodyContent(response)
        }
    }

    /// The bar above the body. It stays put for every textual body — not only
    /// the ones with a pretty form — so wrapping and Find don't come and go
    /// with the content type.
    @ViewBuilder
    private func bodyToolbar(_ response: ApiResponse) -> some View {
        if response.format.isTextual, !response.body.isEmpty {
            HStack(spacing: 8) {
                if response.prettyBody != nil {
                    Picker("", selection: $showRaw) {
                        Text("Pretty").tag(false)
                        Text("Raw").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                Button { wraps.toggle() } label: {
                    Image(systemName: wraps ? "text.alignleft" : "arrow.left.and.right")
                }
                .buttonStyle(.borderless)
                .help(wraps ? "Wrap long lines (on)" : "Wrap long lines (off)")

                Button { findToken += 1 } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
                    .help("Find in body (⌘F)")

                copyButton("Copy the body as shown") { bodyText(response) }

                Spacer()
                Text(response.mediaType.isEmpty ? response.format.rawValue : response.mediaType)
                    .font(.app(.caption2, design: .monospaced))
                    .foregroundStyle(.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func bodyContent(_ response: ApiResponse) -> some View {
        if response.body.isEmpty {
            Text("No response body.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if response.format == .image, let image = NSImage(data: response.body) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if let text = displayText(response) {
            ApiBodyTextView(
                text: text, format: response.format, wraps: wraps, findToken: findToken
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "doc.zipper").font(.largeTitle).foregroundStyle(.textMuted)
                Text("\(response.sizeText) of binary data")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                Button("Save to File…") { saveBody(response) }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func headersTab(_ response: ApiResponse) -> some View {
        Group {
            if response.headers.isEmpty {
                Text("No headers.")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    sectionBar(
                        "\(response.headers.count) headers",
                        copyHelp: "Copy all response headers"
                    ) { headerText(response) }
                    Divider()
                List(Array(response.headers.enumerated()), id: \.offset) { _, header in
                    HStack(alignment: .top, spacing: 8) {
                        // A fixed column truncated the long names that matter
                        // (`strict-transport-security`, `content-security-policy`);
                        // this holds the column but lets a long name have more.
                        Text(header.key)
                            .font(.app(.caption, design: .monospaced))
                            .bold()
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: 170, alignment: .leading)
                        Text(header.value)
                            .font(.app(.caption, design: .monospaced))
                            .foregroundStyle(.textMuted)
                            .textSelection(.enabled)
                    }
                    .contextMenu {
                        Button("Copy Value") { copy(header.value) }
                        Button("Copy Name") { copy(header.key) }
                        Button("Copy Line") { copy("\(header.key): \(header.value)") }
                    }
                }
                .listStyle(.plain)
                .translucentListBackground()
                }
            }
        }
    }

    private func cookiesTab(_ response: ApiResponse) -> some View {
        let cookies = response.cookies
        return Group {
            if cookies.isEmpty {
                Text("This response set no cookies.")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    sectionBar(
                        cookies.count == 1 ? "1 cookie" : "\(cookies.count) cookies",
                        copyHelp: "Copy every cookie this response set"
                    ) { cookieText(cookies) }
                    Divider()
                List(cookies) { cookie in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(cookie.name)
                                .font(.app(.caption, design: .monospaced))
                                .bold()
                            if cookie.httpOnly { flag("HttpOnly") }
                            if cookie.secure { flag("Secure") }
                            if !cookie.sameSite.isEmpty { flag("SameSite=\(cookie.sameSite)") }
                        }
                        Text(cookie.value)
                            .font(.app(.caption2, design: .monospaced))
                            .foregroundStyle(.textMuted)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Text(cookieDetail(cookie))
                            .font(.app(.caption2))
                            .foregroundStyle(.textMuted)
                    }
                    .contextMenu {
                        Button("Copy Value") { copy(cookie.value) }
                        Button("Copy as Cookie Header") {
                            copy("\(cookie.name)=\(cookie.value)")
                        }
                    }
                }
                .listStyle(.plain)
                .translucentListBackground()
                }
            }
        }
    }

    private func cookieText(_ cookies: [ApiCookie]) -> String {
        cookies.map { cookie in
            let detail = cookieDetail(cookie)
            let line = "\(cookie.name)=\(cookie.value)"
            return detail.isEmpty ? line : "\(line) · \(detail)"
        }
        .joined(separator: "\n")
    }

    private func cookieDetail(_ cookie: ApiCookie) -> String {
        var parts: [String] = []
        if !cookie.domain.isEmpty { parts.append("domain \(cookie.domain)") }
        if !cookie.path.isEmpty { parts.append("path \(cookie.path)") }
        if !cookie.maxAge.isEmpty { parts.append("max-age \(cookie.maxAge)") }
        if !cookie.expires.isEmpty { parts.append("expires \(cookie.expires)") }
        return parts.joined(separator: " · ")
    }

    private func flag(_ text: String) -> some View {
        Text(text)
            .font(.app(.caption2))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    private func timingTab(_ response: ApiResponse) -> some View {
        VStack(spacing: 0) {
            sectionBar("Timing", copyHelp: "Copy the timing breakdown") {
                timingText(response)
            }
            Divider()
            timingForm(response)
        }
    }

    private func timingText(_ response: ApiResponse) -> String {
        var lines: [String] = []
        if let timing = response.timing {
            let phases: [(String, Double?)] = [
                ("DNS lookup", timing.dns), ("Connect", timing.connect),
                ("TLS handshake", timing.tls), ("First byte", timing.firstByte),
                ("Total", timing.total),
            ]
            for (name, value) in phases {
                guard let value else { continue }
                lines.append(String(format: "%@: %.0f ms", name, value))
            }
        } else {
            lines.append(String(format: "Total: %.0f ms", response.elapsedMs))
        }
        if !response.finalURL.isEmpty { lines.append("Final URL: \(response.finalURL)") }
        if let prepared = model.prepared {
            lines.append("Sent bytes: \(ApiResponse.formatBytes(prepared.body?.count ?? 0))")
        }
        for hop in response.redirects {
            lines.append("\(hop.statusCode) \(hop.from) -> \(hop.to)")
        }
        return lines.joined(separator: "\n")
    }

    private func timingForm(_ response: ApiResponse) -> some View {
        Form {
            Section("Timing") {
                if let timing = response.timing {
                    row("DNS lookup", timing.dns)
                    row("Connect", timing.connect)
                    row("TLS handshake", timing.tls)
                    row("First byte", timing.firstByte)
                    row("Total", timing.total)
                } else {
                    Text(String(format: "Total %.0f ms", response.elapsedMs))
                        .font(.app(.caption, design: .monospaced))
                }
            }

            Section("Request") {
                LabeledContent("Final URL") {
                    Text(response.finalURL)
                        .font(.app(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let prepared = model.prepared {
                    LabeledContent("Sent bytes") {
                        Text(ApiResponse.formatBytes(prepared.body?.count ?? 0))
                            .font(.app(.caption, design: .monospaced))
                    }
                }
            }

            if !response.redirects.isEmpty {
                Section("Redirects") {
                    ForEach(Array(response.redirects.enumerated()), id: \.offset) { _, hop in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(hop.statusCode) → \(hop.to)")
                                .font(.app(.caption, design: .monospaced))
                            Text("from \(hop.from)")
                                .font(.app(.caption2))
                                .foregroundStyle(.textMuted)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .translucentListBackground()
    }

    @ViewBuilder
    private func row(_ label: String, _ value: Double?) -> some View {
        if let value {
            LabeledContent(label) {
                Text(String(format: "%.0f ms", value)).font(.app(.caption, design: .monospaced))
            }
        }
    }

    // MARK: - States

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(error)
                .font(.app(.callout))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button("Try Again") { model.send() }
                .buttonStyle(.bordered)
                .disabled(!model.canSend)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "paperplane")
                .font(.largeTitle)
                .foregroundStyle(.textMuted)
            Text("Enter a URL and press Send (⌘⏎)")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
            Text("Pasting a cURL command into the URL field imports it.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func displayText(_ response: ApiResponse) -> String? {
        if !showRaw, let pretty = response.prettyBody { return pretty }
        return response.bodyString
    }

    private func bodyText(_ response: ApiResponse) -> String {
        displayText(response) ?? ""
    }

    private func headerText(_ response: ApiResponse) -> String {
        response.headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveBody(_ response: ApiResponse) {
        let name = "response\(ApiResponsePane.fileExtension(for: response))"
        guard let url = ApiClientFilePanels.askSave(suggestedName: name) else { return }
        if let failure = model.saveResponseBody(to: url) { alertMessage = failure }
    }

    static func fileExtension(for response: ApiResponse) -> String {
        switch response.format {
        case .json: return ".json"
        case .xml: return ".xml"
        case .html: return ".html"
        case .text: return ".txt"
        case .image: return imageExtension(response.mediaType)
        case .binary: return ".bin"
        }
    }

    private static func imageExtension(_ mediaType: String) -> String {
        switch mediaType {
        case "image/png": return ".png"
        case "image/jpeg": return ".jpg"
        case "image/gif": return ".gif"
        case "image/webp": return ".webp"
        case "image/svg+xml": return ".svg"
        default: return ".img"
        }
    }
}
