#if !APPSTORE
import SwiftUI
import WebKit

/// The post-update changelog sheet: shown once, on the first launch of a
/// version this updater installed (the notes were stashed when the install
/// was staged — see `UpdaterViewModel.takeWhatsNewForLaunch`).
struct WhatsNewView: View {
    let whatsNew: UpdaterViewModel.WhatsNew
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let notes = whatsNew.notesHTML {
                ReleaseNotesHTMLView(html: notes)
            } else {
                // An update staged without embedded notes (shouldn't happen
                // with our appcast) still gets a friendly landing.
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.app(.largeTitle))
                        .foregroundStyle(.brandAccent)
                    Text("Droidective was updated to \(whatsNew.version).")
                        .font(.app(.body))
                        .foregroundStyle(.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 540)
        .background(.bgRoot)
    }

    /// Accent-badged masthead: eyebrow + version title, with an "up to date"
    /// seal on the trailing edge.
    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.brandAccent, Color.brandAccent.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: "sparkles")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("WHAT'S NEW")
                    .font(.app(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Color.brandAccent)
                Text("Droidective \(whatsNew.version)")
                    .font(.app(.title2).weight(.bold))
            }
            Spacer(minLength: 12)
            Label("Up to date", systemImage: "checkmark.seal.fill")
                .font(.app(.caption).weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Continue") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.brandAccent)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Hangs the What's New sheet off RootView, driven by
/// `AppState.presentWhatsNew` (set by the update notification's "What's
/// New" button). A separate modifier (with its own background host view) so
/// RootView.body neither grows another sheet collision nor more
/// type-checking work — it's already at the limit.
struct WhatsNewPresenter: ViewModifier {
    @Environment(AppState.self) private var state

    func body(content: Content) -> some View {
        @Bindable var state = state
        return content.background {
            Color.clear.sheet(isPresented: $state.presentWhatsNew) {
                if let info = state.whatsNew {
                    WhatsNewView(whatsNew: info) { state.presentWhatsNew = false }
                }
            }
        }
    }
}

/// Renders the appcast item's embedded HTML notes. Links open in the
/// browser; the page itself never navigates. The notes ship a base style in
/// the appcast; `styled` layers app-side CSS over it so the sheet reads like
/// the app — the user's accent on links/markers, sectioned headings, and a
/// transparent canvas over the sheet background.
private struct ReleaseNotesHTMLView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        // Release notes are static HTML — scripts stay off (the coordinator's
        // `evaluateJavaScript` scroll pin is unaffected; that switch only
        // governs content-loaded scripts).
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        // Let the sheet's own background show through instead of the page
        // canvas painting a second, slightly-off surface.
        view.underPageBackgroundColor = .clear
        view.setValue(false, forKey: "drawsBackground")
        // The appcast notes declare `color-scheme: light dark`, so the text
        // follows the app's appearance on its own.
        view.loadHTMLString(Self.styled(html), baseURL: nil)
        return view
    }

    /// Append an app-side style layer — later rules win at equal specificity,
    /// so this restyles the appcast's baseline without the release pipeline
    /// changing.
    static func styled(_ notes: String) -> String {
        let accent = UserDefaults.standard.string(forKey: accentColorDefaultsKey)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "#2f9e44"
        return notes + """
        <style>
        html, body { background: transparent; }
        body { padding: 16px 22px 24px; }
        body > p:first-of-type { font-size: 1.06em; color: color-mix(in srgb, currentColor 75%, transparent); margin-bottom: 1em; }
        h2, h3 { font-weight: 700; }
        h3 { margin: 1.5em 0 .45em; padding-bottom: .35em; border-bottom: 1px solid color-mix(in srgb, currentColor 14%, transparent); }
        li { margin: .38em 0; }
        li::marker { color: \(accent); }
        a { color: \(accent); }
        </style>
        """
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// The sheet lays the webview out after the HTML loads, which can
        /// leave the restored scroll position mid-document — pin to the top.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.scrollTo(0, 0)")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
#endif
