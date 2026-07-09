import ADBKit
import AppKit
import SwiftUI

/// An NSTextView-backed log pane. Unlike the SwiftUI row list (whose
/// `.textSelection` is trapped inside each row), this gives real cross-line
/// selection with native drag autoscroll, ⌘C, and Select All over the whole
/// buffer. Appends are incremental and the ring buffer's head-trim deletes
/// characters instead of rebuilding, so a full 5000-line buffer streams
/// smoothly.
struct SelectableLogView: NSViewRepresentable {
    let lines: [LogLine]
    let search: String
    /// Which ends the viewport touches and whether it can scroll at all — the
    /// caller feeds this to the shared `LogJumpControls`. While parked at the
    /// bottom the view follows new lines; scrolling away pauses that.
    @Binding var edges: LogScrollEdges
    /// Bump the token to snap the view to the requested edge.
    let jump: LogJumpRequest?
    let onFilterTag: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(edges: $edges)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LogTextView()
        // Head-trims measure the deleted height through the TextKit 1 layout
        // manager; touch it before any content lands so the view starts in
        // TextKit 1 instead of downgrading mid-stream.
        _ = textView.layoutManager
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.install(textView: textView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onFilterTag = onFilterTag
        context.coordinator.update(lines: lines, search: search)
        context.coordinator.handleJump(jump)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private let edges: Binding<LogScrollEdges>
        var onFilterTag: ((String) -> Void)?

        private weak var textView: LogTextView?
        private weak var scrollView: NSScrollView?

        /// What the text storage currently shows, line by line. `lineLengths`
        /// holds each line's UTF-16 length (newline included) so a head-trim
        /// knows exactly how many characters to delete.
        private var renderedLines: [LogLine] = []
        private var lineLengths: [Int] = []
        private var renderedSearch = ""
        private var lastJumpToken: Int?

        init(edges: Binding<LogScrollEdges>) {
            self.edges = edges
        }

        func install(textView: LogTextView, scrollView: NSScrollView) {
            self.textView = textView
            self.scrollView = scrollView
            textView.lineAt = { [weak self] characterIndex in
                self?.line(atCharacter: characterIndex)
            }
            textView.filterTag = { [weak self] tag in
                self?.onFilterTag?(tag)
            }
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrolled),
                name: NSView.boundsDidChangeNotification, object: scrollView.contentView
            )
        }

        @objc private func scrolled() {
            syncEdges()
        }

        private func syncEdges() {
            let measured = measuredEdges
            guard measured != edges.wrappedValue else { return }
            // This can run inside a SwiftUI update pass (scroll notifications,
            // updateNSView) — defer the state write out of it.
            Task { @MainActor in
                self.edges.wrappedValue = measured
            }
        }

        /// Within 30 points of an edge still counts as touching it, covering
        /// sub-pixel rounding and the follow scroll itself.
        private var measuredEdges: LogScrollEdges {
            guard let scrollView, let document = scrollView.documentView else {
                return LogScrollEdges()
            }
            let visible = scrollView.contentView.bounds
            return LogScrollEdges(
                atTop: visible.minY <= 30,
                atBottom: visible.maxY >= document.frame.height - 30,
                isScrollable: document.frame.height > visible.height + 1
            )
        }

        /// Following new lines is the bottom-edge state; `update` consults it
        /// before appending to decide whether to keep the view pinned there.
        private var isAtBottom: Bool { measuredEdges.atBottom }

        func handleJump(_ request: LogJumpRequest?) {
            guard let request, request.token != lastJumpToken else { return }
            lastJumpToken = request.token
            switch request.edge {
            case .top: scrollToTop()
            case .bottom: scrollToBottom()
            }
        }

        // MARK: Content diffing

        /// The stream only ever drops lines at the head (ring trim) and
        /// appends at the tail, so those paths are surgical edits; anything
        /// else (filter change, clear, search change) rebuilds.
        func update(lines: [LogLine], search: String) {
            guard let storage = textView?.textStorage else { return }
            let wasTailing = renderedLines.isEmpty || isAtBottom

            defer {
                if wasTailing { scrollToBottom() }
                // Appends below the viewport don't fire a scroll notification,
                // so the edge state must also sync here or the jump buttons
                // never update while parked in scrollback.
                syncEdges()
            }

            if search != renderedSearch {
                renderedSearch = search
                rebuild(lines, in: storage)
                return
            }
            switch LogStreamDiff.plan(rendered: renderedLines.map(\.id), incoming: lines.map(\.id)) {
            case .unchanged:
                return
            case .rebuild:
                rebuild(lines, in: storage)
            case .edit(let dropHead, let appendFrom):
                if dropHead > 0 {
                    trimHead(dropHead, in: storage, keepScrollPlace: !wasTailing)
                }
                if lines.count > appendFrom {
                    append(Array(lines[appendFrom...]), to: storage)
                }
            }
        }

        /// Deletes the first `count` rendered lines. While the user is parked
        /// in scrollback, the deleted height is subtracted from the scroll
        /// offset so the lines being read hold still — without this every
        /// ring trim yanked the scrollback up by the trimmed amount.
        private func trimHead(_ count: Int, in storage: NSTextStorage, keepScrollPlace: Bool) {
            let headLength = lineLengths.prefix(count).reduce(0, +)
            let trimmedHeight = keepScrollPlace ? height(ofFirstCharacters: headLength) : 0
            storage.deleteCharacters(in: NSRange(location: 0, length: headLength))
            renderedLines.removeFirst(count)
            lineLengths.removeFirst(count)
            if trimmedHeight > 0, let scrollView {
                let clip = scrollView.contentView
                var origin = clip.bounds.origin
                origin.y = max(0, origin.y - trimmedHeight)
                clip.scroll(to: origin)
                scrollView.reflectScrolledClipView(clip)
            }
        }

        /// The rendered height of the leading `length` characters — what a
        /// head-trim is about to delete. Everything above the viewport is
        /// already laid out, so this is a lookup, not a fresh layout pass.
        private func height(ofFirstCharacters length: Int) -> CGFloat {
            guard length > 0, let textView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return 0 }
            let glyphs = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil
            )
            return layoutManager.boundingRect(forGlyphRange: glyphs, in: container).height
        }

        private func rebuild(_ lines: [LogLine], in storage: NSTextStorage) {
            renderedLines = []
            lineLengths = []
            storage.setAttributedString(NSAttributedString())
            append(lines, to: storage)
        }

        private func append(_ lines: [LogLine], to storage: NSTextStorage) {
            guard !lines.isEmpty else { return }
            let batch = NSMutableAttributedString()
            for line in lines {
                let attributed = Self.attributedLine(line, search: renderedSearch)
                lineLengths.append(attributed.length)
                batch.append(attributed)
            }
            renderedLines.append(contentsOf: lines)
            storage.append(batch)
        }

        private func scrollToBottom() {
            guard let textView, let storage = textView.textStorage else { return }
            textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
        }

        private func scrollToTop() {
            guard let scrollView else { return }
            let clip = scrollView.contentView
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: 0))
            scrollView.reflectScrolledClipView(clip)
        }

        /// The line under a character index — prefix-sums `lineLengths` (the
        /// context menu's one lookup; not worth a cached table).
        private func line(atCharacter index: Int) -> LogLine? {
            var remaining = index
            for (offset, length) in lineLengths.enumerated() {
                if remaining < length { return renderedLines[offset] }
                remaining -= length
            }
            return renderedLines.last
        }

        // MARK: Rendering

        private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        private static func color(for level: String) -> NSColor {
            switch level {
            case "E", "F": return .systemRed
            case "W": return .systemOrange
            case "I": return .labelColor
            default: return .secondaryLabelColor
            }
        }

        static func display(_ line: LogLine) -> String {
            line.level.isEmpty
                ? line.raw
                : "\(line.time)  \(line.pid)  \(line.level)/\(line.tag): \(line.message)"
        }

        /// One rendered line (newline included), with the search matches
        /// highlighted the way the old row list did.
        static func attributedLine(_ line: LogLine, search: String) -> NSAttributedString {
            let text = display(line) + "\n"
            let attributed = NSMutableAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color(for: line.level),
            ])
            guard !search.isEmpty else { return attributed }
            let haystack = text as NSString
            var location = 0
            while location < haystack.length {
                let range = haystack.range(
                    of: search, options: .caseInsensitive,
                    range: NSRange(location: location, length: haystack.length - location)
                )
                guard range.location != NSNotFound else { break }
                attributed.addAttribute(
                    .backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35),
                    range: range
                )
                location = range.location + range.length
            }
            return attributed
        }
    }
}

/// Adds the per-line context menu (filter by tag, copy line) on top of the
/// text view's native Copy/Select All.
final class LogTextView: NSTextView {
    var lineAt: ((Int) -> LogLine?)?
    var filterTag: ((String) -> Void)?
    private var menuLine: LogLine?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        menuLine = lineAt?(characterIndexForInsertion(at: point))
        let menu = NSMenu()
        if let line = menuLine {
            if !line.tag.isEmpty {
                let item = NSMenuItem(
                    title: "Filter by tag \u{201C}\(line.tag)\u{201D}",
                    action: #selector(filterByTag(_:)), keyEquivalent: ""
                )
                item.target = self
                menu.addItem(item)
            }
            let copyLine = NSMenuItem(title: "Copy Line", action: #selector(copyLine(_:)), keyEquivalent: "")
            copyLine.target = self
            menu.addItem(copyLine)
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    @objc private func filterByTag(_ sender: Any?) {
        if let tag = menuLine?.tag, !tag.isEmpty {
            filterTag?(tag)
        }
    }

    @objc private func copyLine(_ sender: Any?) {
        guard let line = menuLine else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line.raw, forType: .string)
    }
}
