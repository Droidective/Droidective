import ADBKit
import AppKit
import SwiftUI

/// The response (and generated-code) viewer: a read-only `NSTextView` with
/// syntax colouring, an optional soft wrap, and AppKit's own find bar.
///
/// It replaces a `Text` inside a two-axis `ScrollView`. That combination could
/// not size a large body — a bidirectional scroll view proposes `nil` in both
/// axes, so the `maxWidth`/`maxHeight: .infinity` frame had nothing to resolve
/// against — and left the body blank until a click forced the selectable text
/// layer to lay itself out, blank again as soon as focus left. A text view owns
/// its own scrolling and typesetting, so the body is simply always there.
struct ApiBodyTextView: NSViewRepresentable {
    let text: String
    let format: ResponseFormat
    /// Soft wrap. Off, the view scrolls horizontally and long lines stay intact.
    let wraps: Bool
    /// Bump to open the find bar (the feature's ⌘F lands here).
    var findToken: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        // Regions never scrolled into carry an estimated height instead of
        // being typeset — the same reason the log view enables it, and what
        // keeps a multi-megabyte body affordable to open.
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // LogScrollView applies the document width only once a resize settles,
        // so dragging the pane divider doesn't re-wrap the whole body per tick.
        let scrollView = LogScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.install(textView: textView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(text: text, format: format, wraps: wraps)
        context.coordinator.handleFind(findToken)
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?

        private var renderedText: String?
        private var renderedFormat: ResponseFormat?
        private var renderedWraps: Bool?
        private var lastFindToken = 0

        func install(textView: NSTextView, scrollView: NSScrollView) {
            self.textView = textView
            self.scrollView = scrollView
        }

        func update(text: String, format: ResponseFormat, wraps: Bool) {
            guard let textView else { return }
            if renderedWraps != wraps {
                renderedWraps = wraps
                apply(wraps: wraps, to: textView)
            }
            guard renderedText != text || renderedFormat != format else { return }
            renderedText = text
            renderedFormat = format

            let storage = textView.textStorage
            storage?.beginEditing()
            storage?.setAttributedString(Self.attributed(text, format: format))
            storage?.endEditing()
            // A new body starts at the top, not wherever the last one was read.
            textView.scroll(NSPoint(x: 0, y: 0))
        }

        func handleFind(_ token: Int) {
            guard token != lastFindToken else { return }
            lastFindToken = token
            guard token > 0, let textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.performTextFinderAction(findMenuItem)
        }

        /// `performTextFinderAction` reads the action off the sender's tag —
        /// there is no typed API for "open the find bar".
        private lazy var findMenuItem: NSMenuItem = {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            return item
        }()

        private func apply(wraps: Bool, to textView: NSTextView) {
            guard let container = textView.textContainer else { return }
            if wraps {
                container.widthTracksTextView = true
                container.size = NSSize(
                    width: scrollView?.contentSize.width ?? textView.frame.width,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = []
                scrollView?.hasHorizontalScroller = false
            } else {
                container.widthTracksTextView = false
                container.size = NSSize(
                    width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = true
                textView.autoresizingMask = []
                scrollView?.hasHorizontalScroller = true
            }
            scrollView?.tile()
        }

        /// Builds the coloured body. One `addAttribute` per token over a single
        /// editing transaction — the tokenizer already declines bodies too large
        /// to be worth colouring, and those render in the base style.
        static func attributed(_ text: String, format: ResponseFormat) -> NSAttributedString {
            let base: [NSAttributedString.Key: Any] = [
                .font: ApiSyntaxTheme.font,
                .foregroundColor: ApiSyntaxTheme.plain,
            ]
            let string = NSMutableAttributedString(string: text, attributes: base)
            let tokens = SyntaxHighlighter.tokens(for: text, format: format)
            guard !tokens.isEmpty else { return string }

            let length = string.length
            string.beginEditing()
            for token in tokens {
                guard token.location >= 0, token.length > 0,
                    token.location + token.length <= length
                else { continue }
                string.addAttribute(
                    .foregroundColor,
                    value: ApiSyntaxTheme.color(for: token.kind),
                    range: NSRange(location: token.location, length: token.length)
                )
            }
            string.endEditing()
            return string
        }
    }
}

/// Token colours for the response viewer. Unlike the JS console — a fixed dark
/// console by design — this pane sits on the app's own (possibly translucent,
/// possibly light) surface, so every colour is a dynamic `NSColor` that resolves
/// per appearance.
enum ApiSyntaxTheme {

    static var font: NSFont {
        NSFont.monospacedSystemFont(
            ofSize: AppFontPrefs.pointSize(for: .body) * AppFontPrefs.sizeScale, weight: .regular
        )
    }

    static var plain: NSColor { .labelColor }

    static func color(for kind: SyntaxToken.Kind) -> NSColor {
        switch kind {
        case .key: dynamic(light: 0x0B_6E_99, dark: 0x9C_DC_FE)
        case .string, .value: dynamic(light: 0xA3_11_5C, dark: 0xCE_91_78)
        case .number: dynamic(light: 0x09_69_59, dark: 0xB5_CE_A8)
        case .literal: dynamic(light: 0x00_00_FF, dark: 0x56_9C_D6)
        case .tag: dynamic(light: 0x80_00_00, dark: 0x4E_C9_B0)
        case .attribute: dynamic(light: 0xE5_00_00, dark: 0x9C_DC_FE)
        case .comment: dynamic(light: 0x00_80_00, dark: 0x6A_99_55)
        case .declaration: .secondaryLabelColor
        case .punctuation: .tertiaryLabelColor
        }
    }

    private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }
}

extension NSColor {
    fileprivate convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
