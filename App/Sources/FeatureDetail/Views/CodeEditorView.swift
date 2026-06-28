import AppKit
import SwiftUI
import WebKit

/// A read-only source viewer backed by the bundled, offline CodeMirror 6 editor
/// (App/Resources/codemirror-editor.html): syntax highlighting, line numbers,
/// code folding, and ⌘F find / find-and-replace. `content`/`language` are pushed
/// into the editor as they change; bumping `findToken` opens the find panel.
struct CodeEditorView: NSViewRepresentable {
    let content: String
    /// "java", "xml", or "" (plain text — e.g. smali).
    let language: String
    /// 1-based line to scroll to and highlight (0 = top, no highlight).
    var line: Int = 0
    var findToken: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.underPageBackgroundColor = NSColor(red: 0.157, green: 0.173, blue: 0.204, alpha: 1) // #282c34
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        // Seed the desired content so it's applied once the page finishes loading,
        // even if SwiftUI hasn't called updateNSView yet.
        context.coordinator.request(content: content, language: language, line: line)
        if let url = Bundle.main.url(forResource: "codemirror-editor", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.request(content: content, language: language, line: line)
        context.coordinator.find(token: findToken)
    }

    /// Pushes content into the web view over the fire-and-forget
    /// `evaluateJavaScript` bridge — which fails transiently while the page is
    /// mid-load or mid-layout. A dropped push used to leave the editor blank
    /// until the file was reselected, so the coordinator holds the *desired*
    /// state, marks it applied only once the JS call **succeeds**, re-applies
    /// whenever the page finishes loading, and retries briefly on error.
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var ready = false
        private var desired: (content: String, language: String, line: Int)?
        private var applied: (content: String, language: String, line: Int)?
        private var attempts = 0
        private let maxAttempts = 20
        private var lastFindToken = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            apply()
        }

        /// Record the latest content the view wants shown and try to apply it.
        func request(content: String, language: String, line: Int) {
            if desired?.content != content || desired?.language != language || desired?.line != line {
                desired = (content, language, line)
                attempts = 0
            }
            apply()
        }

        /// Push `desired` into the editor if it isn't already there. JSON-encodes
        /// the content so any characters survive the bridge; only on a successful
        /// call is it remembered as applied, otherwise it retries shortly.
        private func apply() {
            guard ready, let webView, let want = desired,
                  applied?.content != want.content || applied?.language != want.language || applied?.line != want.line,
                  attempts < maxAttempts,
                  let data = try? JSONEncoder().encode(want.content),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            attempts += 1
            webView.evaluateJavaScript("window.cmLoad(\(json), \"\(want.language)\", \(want.line))") { [weak self] _, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if error == nil {
                        self.applied = want
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                            MainActor.assumeIsolated { self?.apply() }
                        }
                    }
                }
            }
        }

        func find(token: Int) {
            guard token != lastFindToken else { return }
            lastFindToken = token
            guard ready, token > 0 else { return }
            webView?.evaluateJavaScript("window.cmFind()")
        }
    }
}
