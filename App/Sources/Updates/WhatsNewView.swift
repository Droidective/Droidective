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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's new in Droidective \(whatsNew.version)")
                        .font(.app(.title2).weight(.semibold))
                    Text("You're now on the latest version.")
                        .font(.app(.footnote))
                        .foregroundStyle(.textMuted)
                }
                Spacer()
            }
            .padding(20)

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

            HStack {
                Spacer()
                Button("Continue") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
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
/// browser; the page itself never navigates.
private struct ReleaseNotesHTMLView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        // The appcast notes declare `color-scheme: light dark`, so the page
        // canvas follows the app's appearance on its own.
        view.loadHTMLString(html, baseURL: nil)
        return view
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
