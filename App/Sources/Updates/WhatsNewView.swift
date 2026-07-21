#if !APPSTORE
import SwiftUI
import WebKit

/// The post-update changelog sheet: shown once, on the first launch of a
/// version this updater installed (the notes were stashed when the install
/// was staged — see `UpdaterViewModel.takeWhatsNewForLaunch`).
struct WhatsNewView: View {
    let whatsNew: UpdaterViewModel.WhatsNew
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private static let changelogURL = URL(string: "https://droidective.com/changelog/")!

    /// The app's primary text color resolved to a concrete hex for the notes
    /// webview. The WKWebView follows the OS appearance on its own, which goes
    /// black-on-dark whenever the app's theme (custom background, or a scheme
    /// that differs from the system) doesn't match — so we hand it the same
    /// color the rest of the sheet uses.
    private var textColorHex: String {
        let color: Color = customTextRGB.map { Color(rgb: $0) }
            ?? Color.resolved("TextMain", for: colorScheme)
        return color.hexString ?? (colorScheme == .dark ? "#ECECEC" : "#1A1A1A")
    }

    /// The app's accent resolved to a concrete hex so the notes' section
    /// headers/links use the exact same green as the version pill and Continue
    /// button (the raw UserDefaults value is empty when the bundled asset is in
    /// use, which is a different green from the asset).
    private var accentHex: String { Color.brandAccent.hexString ?? "#2f9e44" }

    /// The app's body point size (honoring the user's text-size scale) so the
    /// notes read at the same size as the rest of the app rather than the
    /// webview's larger 16px default.
    private var baseFontPx: Double { 13 * AppFontPrefs.sizeScale }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let notes = whatsNew.notesHTML {
                ReleaseNotesHTMLView(
                    html: notes, textColorHex: textColorHex,
                    accentHex: accentHex, baseFontPx: baseFontPx
                )
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

    /// Masthead: a version pill beside the title, a "latest version" subtitle,
    /// and a close control on the trailing edge.
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("What's new in Droidective")
                        .font(.app(.title2).weight(.bold))
                    Text(whatsNew.version)
                        .font(.app(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.brandAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.brandAccent.opacity(0.35), lineWidth: 1)
                        )
                }
                Text("You're now on the latest version.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.textMuted)
            }
            Spacer(minLength: 12)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack {
            Button {
                openURL(Self.changelogURL)
            } label: {
                Label("See full changelog", systemImage: "arrow.up.right.square")
            }
            // Same rounded-rect border as the version pill, neutral coloring.
            .buttonStyle(PillButtonStyle(
                fill: Color.secondary.opacity(0.10),
                stroke: Color.secondary.opacity(0.35),
                foreground: .textMuted
            ))

            Spacer()

            // Same rounded-rect border as the pill, filled green (primary).
            Button("Continue") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PillButtonStyle(
                    fill: .brandAccent,
                    stroke: .brandAccent,
                    foreground: .white
                ))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Footer buttons that echo the version pill's shape — a 7pt rounded rect with
/// a thin border — so the sheet's chrome reads as one family. Only the colors
/// vary (neutral for the secondary link, filled green for the primary).
private struct PillButtonStyle: ButtonStyle {
    let fill: Color
    let stroke: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.body))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
    /// The app-resolved primary text color, injected so the notes stay legible
    /// on the sheet's themed background (the webview would otherwise follow the
    /// OS appearance and go black-on-dark).
    let textColorHex: String
    /// The app-resolved accent, so section headers/links match the rest of the
    /// sheet's green exactly.
    let accentHex: String
    /// The app's body point size, so the notes match the rest of the app.
    let baseFontPx: Double

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
        // The app injects its own text color (see `styled`) so the notes match
        // the sheet's theme rather than the OS appearance.
        view.loadHTMLString(
            Self.styled(html, textColor: textColorHex, accent: accentHex, baseFontPx: baseFontPx),
            baseURL: nil
        )
        return view
    }

    /// Append an app-side style layer — later rules win at equal specificity,
    /// so this restyles the appcast's baseline without the release pipeline
    /// changing.
    static func styled(_ notes: String, textColor: String, accent: String, baseFontPx: Double) -> String {
        return notes + """
        <style>
        html, body { background: transparent; }
        body { padding: 16px 22px 24px; color: \(textColor); font-size: \(baseFontPx)px; line-height: 1.5; }
        /* Lead paragraph reads as a highlighted callout with an accent rail. */
        body > p:first-of-type {
            font-size: 1em;
            margin: 2px 0 1.5em;
            padding: 12px 14px;
            border: 1px solid color-mix(in srgb, currentColor 12%, transparent);
            border-left: 3px solid \(accent);
            border-radius: 10px;
            background: transparent;
        }
        h2, h3 { font-weight: 700; }
        /* Section headers: accent, with a divider above each. */
        h3 {
            color: \(accent);
            font-size: 1em;
            margin: 1.7em 0 .55em;
            padding-top: 1.5em;
            border-top: 1px solid color-mix(in srgb, currentColor 12%, transparent);
        }
        h3:first-of-type { border-top: none; padding-top: 0; margin-top: .2em; }
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
