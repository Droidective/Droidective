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
        if let url = Bundle.main.url(forResource: "codemirror-editor", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(content: content, language: language, line: line)
        context.coordinator.find(token: findToken)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var ready = false
        private var pending: (String, String, Int)?
        private var loaded: (String, String, Int)?
        private var lastFindToken = 0

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            if let (text, language, line) = pending {
                pending = nil
                run(text, language, line)
            }
        }

        func load(content: String, language: String, line: Int) {
            guard loaded?.0 != content || loaded?.1 != language || loaded?.2 != line else { return }
            loaded = (content, language, line)
            if ready { run(content, language, line) } else { pending = (content, language, line) }
        }

        func find(token: Int) {
            guard token != lastFindToken else { return }
            lastFindToken = token
            guard ready, token > 0 else { return }
            webView?.evaluateJavaScript("window.cmFind()")
        }

        /// Encode `content` as a JS string literal via JSON so any characters in
        /// the source survive the bridge.
        private func run(_ content: String, _ language: String, _ line: Int) {
            guard let webView,
                  let data = try? JSONEncoder().encode(content),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.cmLoad(\(json), \"\(language)\", \(line))")
        }
    }
}
