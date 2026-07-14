import ADBKit
import AppKit
import SwiftUI

/// An NSTextView-backed log pane. Unlike the SwiftUI row list (whose
/// `.textSelection` is trapped inside each row), this gives real cross-line
/// selection with native drag autoscroll, ⌘C, and Select All over the whole
/// buffer. Appends are incremental and the ring buffer's head-trim deletes
/// characters instead of rebuilding, so a full 5000-line buffer streams
/// smoothly. With `newestFirst` on, the same surgical edits run mirrored —
/// new lines prepend at the top and ring trims delete from the bottom — so
/// the reversed feed streams just as smoothly.
struct SelectableLogView: NSViewRepresentable {
    /// Chronological (oldest first) regardless of display order — the
    /// coordinator reverses at the rendering boundary.
    let lines: [LogLine]
    let search: String
    /// Display order: false reads oldest-top/newest-bottom (terminal style),
    /// true flips the feed so new lines land at the top.
    let newestFirst: Bool
    /// Which ends the viewport touches and whether it can scroll at all — the
    /// caller feeds this to the shared `LogJumpControls`. While parked at the
    /// newest edge the view follows new lines; scrolling away pauses that.
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
        context.coordinator.update(lines: lines, search: search, newestFirst: newestFirst)
        context.coordinator.handleJump(jump)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private let edges: Binding<LogScrollEdges>
        var onFilterTag: ((String) -> Void)?

        private weak var textView: LogTextView?
        private weak var scrollView: NSScrollView?

        /// What the text storage currently shows, line by line, in *display*
        /// order (reversed from the stream when `renderedNewestFirst` is on).
        /// `lineLengths` holds each line's UTF-16 length (newline included) so
        /// a trim knows exactly how many characters to delete.
        private var renderedLines: [LogLine] = []
        private var lineLengths: [Int] = []
        private var renderedSearch = ""
        private var renderedNewestFirst = false
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

        /// Whether the viewport touches the edge new lines land on — `update`
        /// consults it before editing to decide whether to keep the view
        /// pinned there (the follow behavior).
        private func isAtNewestEdge(newestFirst: Bool) -> Bool {
            newestFirst ? measuredEdges.atTop : measuredEdges.atBottom
        }

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
        /// appends at the tail, so those paths are surgical edits — mirrored
        /// (prepend + tail-trim) when the display order is newest-first;
        /// anything else (filter change, clear, search change, an order flip)
        /// rebuilds.
        func update(lines: [LogLine], search: String, newestFirst: Bool) {
            guard let storage = textView?.textStorage else { return }
            // Judged against the *rendered* orientation, so flipping the order
            // while parked on the newest line keeps following it at the other
            // edge.
            let wasTailing = renderedLines.isEmpty || isAtNewestEdge(newestFirst: renderedNewestFirst)

            defer {
                if wasTailing { newestFirst ? scrollToTop() : scrollToBottom() }
                // Edits outside the viewport don't fire a scroll notification,
                // so the edge state must also sync here or the jump buttons
                // never update while parked in scrollback.
                syncEdges()
            }

            if search != renderedSearch || newestFirst != renderedNewestFirst {
                renderedSearch = search
                renderedNewestFirst = newestFirst
                rebuild(lines, in: storage)
                return
            }
            // The plan speaks stream order; rendered lines are display order.
            let renderedStreamIDs = newestFirst
                ? renderedLines.reversed().map(\.id)
                : renderedLines.map(\.id)
            switch LogStreamDiff.plan(rendered: renderedStreamIDs, incoming: lines.map(\.id)) {
            case .unchanged:
                return
            case .rebuild:
                rebuild(lines, in: storage)
            case .edit(let dropHead, let appendFrom):
                if newestFirst {
                    // Mirrored: the stream's head-trim is the *bottom* of the
                    // display, its tail-append the *top*.
                    if dropHead > 0 {
                        trimTail(dropHead, in: storage)
                    }
                    if lines.count > appendFrom {
                        prepend(Array(lines[appendFrom...]), to: storage, keepScrollPlace: !wasTailing)
                    }
                } else {
                    if dropHead > 0 {
                        trimHead(dropHead, in: storage, keepScrollPlace: !wasTailing)
                    }
                    if lines.count > appendFrom {
                        append(Array(lines[appendFrom...]), to: storage)
                    }
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
        /// head-trim is about to delete, or what a prepend just inserted. For
        /// a trim everything above the viewport is already laid out, so this
        /// is a lookup; for a prepend it lays out just the fresh batch.
        private func height(ofFirstCharacters length: Int) -> CGFloat {
            guard length > 0, let textView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return 0 }
            let glyphs = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil
            )
            return layoutManager.boundingRect(forGlyphRange: glyphs, in: container).height
        }

        /// Deletes the last `count` rendered lines — the stream's ring trim in
        /// newest-first display. Nothing above the deletion moves, so unlike
        /// `trimHead` the scrollback needs no offset compensation.
        private func trimTail(_ count: Int, in storage: NSTextStorage) {
            let tailLength = lineLengths.suffix(count).reduce(0, +)
            storage.deleteCharacters(in: NSRange(location: storage.length - tailLength, length: tailLength))
            renderedLines.removeLast(count)
            lineLengths.removeLast(count)
        }

        private func rebuild(_ lines: [LogLine], in storage: NSTextStorage) {
            renderedLines = []
            lineLengths = []
            storage.setAttributedString(NSAttributedString())
            append(renderedNewestFirst ? Array(lines.reversed()) : lines, to: storage)
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

        /// Inserts a chronological batch above the current content — the
        /// newest-first twin of `append` (fresh lines land at the top, newest
        /// leading). While the user is parked in scrollback the inserted
        /// height is added to the scroll offset so the lines being read hold
        /// still — the mirror of `trimHead`'s compensation.
        private func prepend(_ lines: [LogLine], to storage: NSTextStorage, keepScrollPlace: Bool) {
            guard !lines.isEmpty else { return }
            let displayLines = Array(lines.reversed())
            let batch = NSMutableAttributedString()
            var batchLengths: [Int] = []
            for line in displayLines {
                let attributed = Self.attributedLine(line, search: renderedSearch)
                batchLengths.append(attributed.length)
                batch.append(attributed)
            }
            storage.insert(batch, at: 0)
            renderedLines.insert(contentsOf: displayLines, at: 0)
            lineLengths.insert(contentsOf: batchLengths, at: 0)
            guard keepScrollPlace, let scrollView else { return }
            let insertedHeight = height(ofFirstCharacters: batch.length)
            guard insertedHeight > 0 else { return }
            let clip = scrollView.contentView
            var origin = clip.bounds.origin
            origin.y += insertedHeight
            clip.scroll(to: origin)
            scrollView.reflectScrolledClipView(clip)
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
