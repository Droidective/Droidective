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
    /// True while the view is parked at the bottom following new lines; the
    /// caller shows its "jump to newest" button when this goes false.
    @Binding var isTailing: Bool
    /// Increment to ask the view to scroll back to the newest line.
    let jumpToken: Int
    let onFilterTag: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isTailing: $isTailing)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LogTextView()
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
        context.coordinator.handleJump(token: jumpToken)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private let isTailing: Binding<Bool>
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

        init(isTailing: Binding<Bool>) {
            self.isTailing = isTailing
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
            syncTailing()
        }

        private func syncTailing() {
            let atBottom = isAtBottom
            guard atBottom != isTailing.wrappedValue else { return }
            // This can run inside a SwiftUI update pass (scroll notifications,
            // updateNSView) — defer the state write out of it.
            Task { @MainActor in
                self.isTailing.wrappedValue = atBottom
            }
        }

        /// Within this many points of the bottom still counts as tailing,
        /// covering sub-pixel rounding and the follow scroll itself.
        private var isAtBottom: Bool {
            guard let scrollView, let document = scrollView.documentView else { return true }
            let visible = scrollView.contentView.bounds
            return visible.maxY >= document.frame.height - 30
        }

        func handleJump(token: Int) {
            guard lastJumpToken != nil, token != lastJumpToken else {
                lastJumpToken = token
                return
            }
            lastJumpToken = token
            scrollToBottom()
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
                // so the follow state must also sync here or the jump button
                // never appears while parked in scrollback.
                syncTailing()
            }

            if search != renderedSearch {
                renderedSearch = search
                rebuild(lines, in: storage)
                return
            }
            // Fast path: nothing changed.
            if lines.count == renderedLines.count,
               lines.first?.id == renderedLines.first?.id,
               lines.last?.id == renderedLines.last?.id {
                return
            }
            guard let first = lines.first else {
                rebuild(lines, in: storage)
                return
            }
            guard let overlapStart = renderedLines.firstIndex(where: { $0.id == first.id }) else {
                rebuild(lines, in: storage)
                return
            }
            let overlap = renderedLines.count - overlapStart
            guard lines.count >= overlap, lines[overlap - 1].id == renderedLines.last?.id else {
                rebuild(lines, in: storage)
                return
            }
            if overlapStart > 0 {
                let headLength = lineLengths.prefix(overlapStart).reduce(0, +)
                storage.deleteCharacters(in: NSRange(location: 0, length: headLength))
                renderedLines.removeFirst(overlapStart)
                lineLengths.removeFirst(overlapStart)
            }
            if lines.count > overlap {
                append(Array(lines[overlap...]), to: storage)
            }
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
