import ADBKit
import AppKit
import SwiftUI

// MARK: - Row layout

/// A wrapping row of console segments — Chrome puts a log's whole argument list
/// on one line (`[app] loaded ▶ {id: 1} ▶ (2) ['a', 'b']`) and only wraps when
/// it runs out of width, rather than stacking each object on a line of its own.
///
/// Segments are laid out on their first text baseline so a disclosure triangle,
/// a run of scalars, and an object preview sit on one visual line.
struct ConsoleFlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 3

    /// Measurements already taken, keyed by width. SwiftUI asks a row for its
    /// size several times per layout pass and then places it, and measuring is
    /// the expensive half — see `ConsoleRowMeasurementCache`. The default
    /// `updateCache` throws the whole memo away whenever the subviews change,
    /// which is what keeps a memoised row honest about its own content.
    func makeCache(subviews _: Subviews) -> ConsoleRowMeasurementCache {
        ConsoleRowMeasurementCache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ConsoleRowMeasurementCache
    ) -> CGSize {
        let arranged = measure(subviews, maxWidth: proposal.width ?? .infinity, cache: &cache).arrangement
        return CGSize(width: arranged.width, height: arranged.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews,
        cache: inout ConsoleRowMeasurementCache
    ) {
        // Measured against the width actually allocated, not the proposal — the
        // two can differ, and laying a row out against anything but its real
        // bounds is how it ends up drawn wider than the pane holding it.
        let measured = measure(subviews, maxWidth: bounds.width, cache: &cache)
        let (segments, arranged) = (measured.segments, measured.arrangement)
        for (index, subview) in subviews.enumerated() {
            let slot = arranged.slots[index]
            // Never offer a segment more width than the row has. A value with
            // no break in it measures wider than the pane, and placed at its
            // measured width it draws straight over whatever is beside the
            // pane; clamped, it truncates inside its own row instead.
            subview.place(
                at: CGPoint(x: bounds.minX + slot.x, y: bounds.minY + slot.y),
                proposal: ProposedViewSize(
                    width: min(segments[index].width, bounds.width), height: segments[index].height
                )
            )
        }
    }

    /// This row measured at `maxWidth`, from the memo when it's already been
    /// asked for at that width and freshly otherwise.
    private func measure(
        _ subviews: Subviews, maxWidth: CGFloat, cache: inout ConsoleRowMeasurementCache
    ) -> ConsoleRowMeasurement {
        if let memoised = cache.measurement(atWidth: maxWidth) { return memoised }
        let fresh = arrange(subviews, maxWidth: maxWidth)
        cache.store(fresh, atWidth: maxWidth)
        return fresh
    }

    /// Measure each segment at the row's width, then hand the arithmetic to
    /// `ConsoleRowLayout` — it's pure, and it's where the wrapping height has to
    /// be right.
    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> ConsoleRowMeasurement {
        var segments: [ConsoleRowSegment] = []
        segments.reserveCapacity(subviews.count)
        for subview in subviews {
            let dimensions = subview.dimensions(in: ProposedViewSize(width: maxWidth, height: nil))
            segments.append(ConsoleRowSegment(
                width: dimensions.width,
                height: dimensions.height,
                baseline: dimensions[VerticalAlignment.firstTextBaseline]
            ))
        }
        let arrangement = ConsoleRowLayout.arrange(
            segments, maxWidth: maxWidth, spacing: spacing, lineSpacing: lineSpacing
        )
        return ConsoleRowMeasurement(segments: segments, arrangement: arrangement)
    }
}

// MARK: - Entry row

/// One console line: the level glyph, the message and its inline object
/// previews, whatever objects the reader expanded, and — at the right edge, the
/// way Chrome ends every row — where the call was made.
struct JSEntryRow: View {
    let entry: JSEntry
    let session: JSConsoleSession
    @State private var hovering = false
    @State private var copied = false
    /// Per-argument disclosure state. It lives on the row rather than inside
    /// each value because the collapsed preview sits inline in the message line
    /// while its expanded tree renders below the whole line — two places that
    /// can't share a child view's own `@State`.
    @State private var expansion: [Int: ArgExpansion] = [:]
    /// The call's stack resolved back to source files, empty until Metro
    /// answers (or forever, when it can't).
    @State private var symbolicatedStack: [SymbolicatedFrame] = []
    @State private var stackShown = false
    /// The grid for a `console.table` row, which Chrome draws above the value's
    /// own disclosure.
    @State private var table: ConsoleTable?
    @Environment(\.logTailScrollToHeader) private var scrollToHeader
    @Environment(\.logTailPauseFollow) private var pauseFollow

    private var query: String { session.findText.trimmingCharacters(in: .whitespaces) }
    private var isCurrentFind: Bool { session.findVisible && session.currentFindID == entry.id }

    /// Disclosure state for one expandable argument.
    private struct ArgExpansion {
        var expanded = false
        var snapshot: SnapNode?
        var loading = false
        var failed = false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            groupIndent
            glyph
            VStack(alignment: .leading, spacing: 3) {
                if let table { ConsoleTableView(table: table) }
                ConsoleFlowLayout { messageSegments }
                    .frame(maxWidth: .infinity, alignment: .leading)
                expandedObjects
                // Chrome keeps a console call's stack folded behind its source
                // link — unfolding every error's would bury the message under
                // eight frames of framework plumbing. A thrown exception is the
                // exception: there the frames *are* the message.
                if stackShown || isThrownException, let stack = entry.stack {
                    StackView(stack: stack, symbolicated: symbolicatedStack)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Always in the layout — hidden, not removed, when idle — so
            // hovering can't change the row's width and reflow its text.
            copyButtons
                .opacity(hovering || copied || stackShown ? 1 : 0)
                .allowsHitTesting(hovering || copied || stackShown)
            // Claims its width before the message does: a clock is a few dozen
            // points, and without the priority the message keeps all of it and
            // pushes the clock off the row entirely.
            timestamp
                .layoutPriority(1)
        }
        .contentShape(Rectangle())
        // The row's own click sits *behind* its content rather than over it, so
        // it can never compete with the copy icons, the source link, or a
        // disclosure inside an expanded value — those get every click that
        // lands on one, and the row keeps the rest.
        //
        // And it only ever *opens* the first object. A click that also
        // collapsed would fire from anywhere inside the expanded tree —
        // including a nested leaf — and fold the whole thing back up under the
        // reader.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { expandPrimaryObject() }
        }
        .onHover { hovering = $0 }
        // Hovering the row is what reveals its URLs' underlines.
        .environment(\.consoleLinkUnderline, hovering)
        .contextMenu { copyMenu }
        .task(id: entry.id) { symbolicatedStack = await session.symbolicated(entry.stack) }
        .task(id: entry.id) {
            guard let objectId = tableArgumentID else { return }
            table = await session.table(for: entry.id, objectId: objectId)
        }
    }

    /// An uncaught exception — the only row whose stack shows unasked.
    private var isThrownException: Bool {
        if case .evalError = entry.kind { return true }
        return false
    }

    private var source: ConsoleSourceLocation? { MetroSymbolicator.location(in: symbolicatedStack) }

    /// The handle behind a `console.table` call's data, when this row is one.
    private var tableArgumentID: String? {
        guard case let .log(_, args, _, isTable) = entry.kind, isTable else { return nil }
        return args.first(where: \.isExpandable)?.objectId
    }

    // MARK: Message segments

    /// The row's message as flow segments: runs of scalars merge into one text
    /// block, each expandable object becomes its own inline disclosure.
    @ViewBuilder private var messageSegments: some View {
        switch entry.kind {
        case let .input(text):
            line(text, base: JSConsoleTheme.muted)
        case let .notice(text):
            line(text, base: JSConsoleTheme.muted)
        case let .evalError(details):
            line(details.message, base: JSConsoleTheme.errorText)
        case let .result(object):
            valueSegment(index: 0, object: object, style: .value, tint: nil)
        case let .log(level, args, _, _):
            let tint: Color? = (level == .error || level == .warning) ? level.consoleTextColor : nil
            ForEach(argRows(args)) { row in
                switch row.kind {
                case let .scalars(tokens):
                    scalarSegment(tokens, tint: tint)
                case let .object(object):
                    valueSegment(index: row.id, object: object, style: .consoleArgument, tint: tint)
                }
            }
        }
    }

    @ViewBuilder private func scalarSegment(_ tokens: [JSToken], tint: Color?) -> some View {
        if let tint {
            line(tokens.map(\.text).joined(), base: tint)
        } else {
            coloredTokenText(tokens, query: query, current: isCurrentFind, underlineLinks: hovering)
                .font(.app(.callout, design: .monospaced))
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A group header is its own toggle: Chrome folds the block from the header
    /// row, and the triangle says which way it goes.
    @ViewBuilder private func valueSegment(
        index: Int, object: RemoteObject, style: JSRenderStyle, tint: Color?
    ) -> some View {
        if object.isExpandable {
            Button {
                toggle(index, object: object)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    disclosureTriangle(open: expansion[index]?.expanded == true)
                    coloredTokenText(
                        object.tokens(style: style), query: query, current: false, underlineLinks: hovering
                    )
                    .font(.app(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show this value's properties")
        } else {
            scalarSegment(object.tokens(style: style), tint: tint)
        }
    }

    /// Every expanded argument's tree, below the message line the way Chrome
    /// renders one.
    @ViewBuilder private var expandedObjects: some View {
        ForEach(expandedIndices, id: \.self) { index in
            if let state = expansion[index] {
                if state.loading {
                    ProgressView().controlSize(.small)
                } else if let snapshot = state.snapshot {
                    ExpandedTree(node: snapshot, session: session)
                        .padding(.leading, 14)
                } else if state.failed {
                    Text("Couldn't read this value.").font(.app(.caption)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var expandedIndices: [Int] {
        expansion.filter(\.value.expanded).keys.sorted()
    }

    // MARK: Gutter, glyph, trailing edge

    /// Chrome's group nesting: an indent per level with a rule down the left of
    /// the block. Capped so a runaway `console.group` can't push a narrow pane's
    /// text off the right edge.
    @ViewBuilder private var groupIndent: some View {
        let levels = min(entry.group.depth, 6)
        if levels > 0 {
            HStack(spacing: 0) {
                ForEach(0 ..< levels, id: \.self) { _ in
                    Rectangle()
                        .fill(JSConsoleTheme.muted.opacity(0.35))
                        .frame(width: 1)
                        .padding(.leading, 11)
                        .padding(.trailing, 4)
                }
            }
            .frame(height: 14)
        }
    }

    /// Chrome marks only the levels that need marking — errors and warnings.
    /// A log/info/debug row starts at its text, so a plain feed reads as text
    /// rather than a column of identical glyphs; the gutter stays reserved so
    /// nothing shifts when one arrives.
    @ViewBuilder private var glyph: some View {
        switch entry.kind {
        case .input:
            icon("chevron.right", JSConsoleTheme.muted)
        case .result:
            icon("arrow.turn.down.right", JSConsoleTheme.muted)
        case .evalError:
            icon("xmark.octagon.fill", JSConsoleTheme.errorText)
        case .notice:
            icon("info.circle", JSConsoleTheme.muted)
        case let .log(level, _, _, _):
            if entry.group.isHeader {
                Button { session.toggleGroup(entry.id) } label: {
                    disclosureTriangle(open: !session.isGroupCollapsed(entry.id))
                        .frame(width: 14)
                        .padding(.top, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(session.isGroupCollapsed(entry.id) ? "Expand this group" : "Collapse this group")
            } else if level == .error || level == .warning {
                icon(level.icon, level.consoleIconColor)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
        }
    }

    private func icon(_ name: String, _ style: some ShapeStyle) -> some View {
        Image(systemName: name)
            .font(.app(.caption))
            .foregroundStyle(style)
            .frame(width: 14)
            .padding(.top, 2)
    }

    private func disclosureTriangle(open: Bool) -> some View {
        Image(systemName: open ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
            .font(.app(size: 8))
            .foregroundStyle(JSConsoleTheme.muted)
    }

    /// The clock, always there — two glanceable words wide, and how you line
    /// the console up against logcat.
    private var timestamp: some View {
        Text(entry.at, format: .dateTime.hour().minute().second())
            .font(.app(.caption2).monospacedDigit())
            .foregroundStyle(JSConsoleTheme.muted)
            .fixedSize()
            .padding(.top, 1)
    }

    /// The icon says nothing on its own, so the tooltip carries the whole
    /// location: file and line, the function, and the full path.
    private func sourceHelp(_ source: ConsoleSourceLocation) -> String {
        let function = source.function.isEmpty ? "" : source.function + "  "
        return "\(source.label)\n\(function)\(source.file) — click for the full stack"
    }

    // MARK: Copy

    /// What a row lets you do, revealed together on hover: copy the whole log,
    /// copy just its object, open where it came from. One weight and one
    /// colour — a written-out `NetworkInterceptors.js:38` costs more width than
    /// the message beside it can spare, and a blue link among grey icons reads
    /// as a different kind of thing when it isn't.
    @ViewBuilder private var copyButtons: some View {
        HStack(spacing: 6) {
            Button(action: copyLog) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.app(.caption))
                    .foregroundStyle(copied ? .green : JSConsoleTheme.muted)
                    // Fixed footprint for both glyphs, so neither hover nor the
                    // copy→checkmark swap nudges the layout.
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .help(primaryObjectID == nil
                ? "Copy this log"
                : "Copy this log — the message and the whole object")

            if primaryObjectID != nil {
                Button(action: copyObject) {
                    Image(systemName: "curlybraces")
                        .font(.app(.caption))
                        .foregroundStyle(JSConsoleTheme.muted)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help("Copy just the object, as JSON")
            }

            if let source {
                Button { stackShown.toggle() } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.app(.caption))
                        .foregroundStyle(JSConsoleTheme.muted)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(sourceHelp(source))
            }
        }
        .padding(.top, 1)
    }

    @ViewBuilder private var copyMenu: some View {
        Button("Copy Log", action: copyLog)
        if primaryObjectID != nil {
            Button("Copy Object as JSON", action: copyObject)
        }
    }

    private func flashCopied() {
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }

    /// The whole log: its message, then every object it carries as real JSON.
    /// The row shows objects as `{…}`, which is exactly the part a paste can't
    /// act on — so the clipboard resolves them.
    private func copyLog() {
        Task {
            copyToPasteboard(await logText())
            flashCopied()
        }
    }

    private func logText() async -> String {
        switch entry.kind {
        case let .log(_, args, _, _):
            let chunks = ConsoleArguments.chunks(args)
            var json: [Int: String] = [:]
            for (index, chunk) in chunks.enumerated() {
                if case let .object(object) = chunk, let text = await stringify(object) {
                    json[index] = text
                }
            }
            return ConsoleArguments.copyText(chunks, json: json)
        case let .result(object):
            return await stringify(object) ?? object.inlineSummary
        default:
            return jsEntryPlainText(entry.kind)
        }
    }

    /// Faithful JSON for a value, or nil when it has no handle or the runtime
    /// couldn't stringify it (the caller falls back to the preview).
    private func stringify(_ object: RemoteObject) async -> String? {
        guard object.isExpandable, let objectId = object.objectId else { return nil }
        return await session.jsonString(of: objectId)
    }

    private func copyObject() {
        guard let objectID = primaryObjectID else { return }
        Task {
            let json = await session.jsonString(of: objectID) ?? jsEntryPlainText(entry.kind)
            copyToPasteboard(json)
            flashCopied()
        }
    }

    /// The object handle to deep-copy as JSON (result value, or the first
    /// expandable log arg).
    private var primaryObjectID: String? {
        switch entry.kind {
        case let .result(object): object.isExpandable ? object.objectId : nil
        case let .log(_, args, _, _): args.first(where: \.isExpandable)?.objectId
        default: nil
        }
    }

    // MARK: Expansion

    private func toggle(_ index: Int, object: RemoteObject) {
        var state = expansion[index] ?? ArgExpansion()
        state.expanded.toggle()
        expansion[index] = state
        guard state.expanded else { return }
        // Expanding means the user is reading — pause tail-follow so streaming
        // lines can't scroll the object away (the jump button or scrolling back
        // resumes), and bring the row's own header to the top so a big value
        // reads from its start instead of the feed reflowing to its end.
        pauseFollow()
        if state.snapshot == nil, !state.loading {
            load(index, object: object)
        } else {
            scrollHeaderToTop(index)
        }
    }

    /// The child rows aren't lazy, so a big object takes a few frames to lay
    /// out; re-issue the scroll over a short window so it lands on the settled
    /// position rather than an early estimate.
    private func scrollHeaderToTop(_ index: Int) {
        Task {
            for delay in [30, 120, 260] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard expansion[index]?.expanded == true else { return }
                scrollToHeader(entry.id)
            }
        }
    }

    /// The row-wide click: open the first expandable argument if it isn't
    /// already. Never a toggle — see the tap gesture's note.
    private func expandPrimaryObject() {
        guard let (index, object) = firstExpandableArgument() else { return }
        guard expansion[index]?.expanded != true else { return }
        toggle(index, object: object)
    }

    private func firstExpandableArgument() -> (Int, RemoteObject)? {
        switch entry.kind {
        case let .result(object):
            return object.isExpandable ? (0, object) : nil
        case let .log(_, args, _, _):
            for row in argRows(args) {
                if case let .object(object) = row.kind { return (row.id, object) }
            }
            return nil
        default:
            return nil
        }
    }

    private func load(_ index: Int, object: RemoteObject) {
        guard let objectId = object.objectId else { return }
        expansion[index]?.loading = true
        Task {
            let node = await session.snapshot(of: objectId)
            var state = expansion[index] ?? ArgExpansion()
            state.snapshot = node
            state.failed = node == nil
            state.loading = false
            expansion[index] = state
            if node != nil { scrollHeaderToTop(index) }
        }
    }

    // MARK: Argument grouping

    /// `ConsoleArguments.chunks` with its position attached — the index doubles
    /// as this row's expansion key, so it has to stay stable across renders.
    private struct ArgRow: Identifiable {
        let id: Int
        let kind: ConsoleArgumentChunk
    }

    private func argRows(_ args: [RemoteObject]) -> [ArgRow] {
        ConsoleArguments.chunks(args).enumerated().map { ArgRow(id: $0.offset, kind: $0.element) }
    }

    private func line(_ text: String, base: Color) -> some View {
        highlightedText(text, query: query, base: base, current: isCurrentFind, underlineLinks: hovering)
            .font(.app(.callout, design: .monospaced))
            .lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Snapshot tree (client-side, no getProperties)

/// An expanded object/array rendered inline (the feed grows to fit — no nested
/// scroll), with a find field for the values big enough to need one. Typing
/// shows a clickable result list (`SnapNode.findMatches`, pure in ADBKit);
/// clicking a result expands the tree along its path and highlights the node.
struct ExpandedTree: View {
    let node: SnapNode
    let session: JSConsoleSession
    @State private var search = ""
    /// Ordinal paths ("0/3/1") of the containers currently open — hoisted here
    /// so a clicked find result can expand its whole ancestor chain.
    @State private var expandedPaths: Set<String> = []
    /// The last revealed find result, tinted until the next find/reveal.
    @State private var highlightedPath: String?

    /// Below this the whole value fits on screen, and a search field over four
    /// properties is a control that costs more room than it saves.
    private static let searchWorthwhileNodes = 25

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        VStack(alignment: .leading, spacing: 4) {
            if node.nodeCount(limit: Self.searchWorthwhileNodes) >= Self.searchWorthwhileNodes {
                SearchField(prompt: "Find in object…", text: $search)
                    .controlSize(.small)
                    .frame(maxWidth: 260)
            }
            if !query.isEmpty {
                SnapMatchList(matches: node.findMatches(query: query), onSelect: reveal)
            } else if node.isContainer {
                SnapChildrenView(
                    node: node, session: session, path: "",
                    expandedPaths: $expandedPaths, highlightedPath: highlightedPath
                )
            } else {
                // A primitive root: a logged `Error` snapshots to its stack
                // string, and rendering only containers left the disclosure
                // opening onto nothing.
                Text(node.text ?? node.primitivePreview)
                    .font(.app(.caption).monospaced())
                    .foregroundStyle(JSConsoleTheme.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // A newly typed query drops the previous reveal's tint (reveal itself
        // clears the field, so its own highlight survives this).
        .onChange(of: search) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespaces).isEmpty { highlightedPath = nil }
        }
    }

    /// Open every container down to the match, mark it, and swap back to the
    /// tree so the user lands on the node.
    private func reveal(_ match: TreeMatch) {
        var path = ""
        for index in match.path {
            path = path.isEmpty ? String(index) : "\(path)/\(index)"
            expandedPaths.insert(path)
        }
        highlightedPath = path
        search = ""
    }
}

/// The clickable results of a find inside one object — location, then value.
private struct SnapMatchList: View {
    let matches: [TreeMatch]
    let onSelect: (TreeMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if matches.isEmpty {
                Text("No matches").font(.app(.caption)).foregroundStyle(.tertiary)
            }
            ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                Button {
                    onSelect(match)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.app(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text("\(match.displayPath):")
                            .font(.app(.callout, design: .monospaced))
                            .foregroundStyle(jsColor(.key))
                        Text(match.preview)
                            .font(.app(.callout, design: .monospaced))
                            .foregroundStyle(jsColor(match.isContainer ? .className : .plain))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reveal in the tree")
            }
            if matches.count >= 200 {
                Text("…first 200 matches — narrow the search")
                    .font(.app(.caption)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The ordered child rows of a container `SnapNode` — array items with index
/// labels, or object entries with key labels. `path` is the container's own
/// ordinal path; expansion state lives in the owning `ExpandedTree` so find
/// results can drive it.
private struct SnapChildrenView: View {
    let node: SnapNode
    let session: JSConsoleSession
    let path: String
    @Binding var expandedPaths: Set<String>
    let highlightedPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if node.type == "array", let items = node.items {
                if items.isEmpty { emptyRow }
                ForEach(Array(items.enumerated()), id: \.offset) { index, child in
                    SnapValueView(
                        label: String(index), node: child, session: session,
                        path: childPath(index), expandedPaths: $expandedPaths,
                        highlightedPath: highlightedPath
                    )
                }
                if let hidden = node.hiddenCount, hidden > 0 { moreRow("…(+\(hidden) more)") }
            } else if let entries = node.entries {
                if entries.isEmpty { emptyRow }
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    SnapValueView(
                        label: entry.name, node: entry.node, session: session,
                        path: childPath(index), expandedPaths: $expandedPaths,
                        highlightedPath: highlightedPath
                    )
                }
                if node.truncated == true { moreRow("…(more)") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func childPath(_ index: Int) -> String {
        path.isEmpty ? String(index) : "\(path)/\(index)"
    }

    private var emptyRow: some View {
        Text(node.type == "array" ? "(empty array)" : "(no enumerable properties)")
            .font(.app(.caption)).foregroundStyle(.tertiary)
    }

    private func moreRow(_ text: String) -> some View {
        Text(text).font(.app(.caption)).foregroundStyle(.tertiary)
    }
}

/// One row in the snapshot tree: a primitive `key: value`, or a collapsible
/// container header whose children (another `SnapChildrenView`) indent below.
/// A collapsed container previews its own first few properties the way Chrome
/// does, so most values can be read without opening them at all.
private struct SnapValueView: View {
    let label: String?
    let node: SnapNode
    let session: JSConsoleSession
    let path: String
    @Binding var expandedPaths: Set<String>
    let highlightedPath: String?
    @Environment(\.logTailPauseFollow) private var pauseFollow
    @Environment(\.consoleLinkUnderline) private var underlineLinks

    /// Text highlighted in rows: the ⌘F find query.
    private var highlight: String { session.findText.trimmingCharacters(in: .whitespaces) }
    private var isOpen: Bool { expandedPaths.contains(path) }
    private var isRevealed: Bool { path == highlightedPath }

    var body: some View {
        if node.isContainer {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if isOpen {
                        expandedPaths.remove(path)
                    } else {
                        expandedPaths.insert(path)
                        // Reading a nested node is still reading — keep the
                        // feed from scrolling it away.
                        pauseFollow()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: isOpen ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                            .font(.app(size: 8))
                            .foregroundStyle(JSConsoleTheme.muted)
                            .frame(width: 14)
                        labelText
                        coloredTokenText(node.previewTokens(), query: highlight, current: false)
                            .font(.app(.callout, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .contentShape(Rectangle())
                    .background(revealTint)
                }
                .buttonStyle(.plain)
                if isOpen {
                    SnapChildrenView(
                        node: node, session: session, path: path,
                        expandedPaths: $expandedPaths, highlightedPath: highlightedPath
                    )
                    .padding(.leading, 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                labelText
                highlightedText(
                    node.primitivePreview, query: highlight, base: jsColor(SnapNode.tokenKind(node.type)),
                    underlineLinks: underlineLinks
                )
                .font(.app(.callout, design: .monospaced))
                .textSelection(.enabled)
            }
            .background(revealTint)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var revealTint: some View {
        if isRevealed {
            RoundedRectangle(cornerRadius: 3).fill(JSConsoleTheme.findMatch.opacity(0.22))
        }
    }

    @ViewBuilder private var labelText: some View {
        if let label {
            highlightedText("\(label):", query: highlight, base: jsColor(.key))
                .font(.app(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// `console.table` as a grid, the way Chrome draws it: an `(index)` column,
/// one column per key across the rows, and a `Value` column for any element
/// that isn't an object. Cells are one line — the value's own disclosure below
/// the table is where a nested one opens.
private struct ConsoleTableView: View {
    let table: ConsoleTable

    private var headers: [String] {
        ["(index)"] + table.columns + (table.hasValueColumn ? ["Value"] : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The grid scrolls inside its own row rather than sizing the feed.
            // A capped `frame` bounds the maximum but not the *ideal* width, and
            // that ideal propagates up: one wide table made every row in the
            // feed as wide as itself, so in a split pane the rest of the rows
            // ran under the pane beside them.
            ScrollView(.horizontal, showsIndicators: false) {
                grid
            }
            .frame(maxWidth: 900, alignment: .leading)
            if table.hiddenRows > 0 {
                Text("…\(table.hiddenRows) more rows")
                    .font(.app(.caption)).foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, name in
                    cell(name, isHeader: true)
                }
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    cell(row.index, isHeader: false)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, text in
                        cell(text, isHeader: false)
                    }
                    if table.hasValueColumn { cell(row.value ?? "", isHeader: false) }
                }
            }
        }
    }

    /// Columns size to a readable minimum rather than sharing the row: inside a
    /// horizontal scroll there is no width to share, and `maxWidth: .infinity`
    /// against an unbounded proposal would grow without limit.
    private func cell(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(.app(.caption, design: .monospaced))
            .foregroundStyle(isHeader ? JSConsoleTheme.text : JSConsoleTheme.muted)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: 72, maxWidth: 260, alignment: .leading)
            .background(isHeader ? JSConsoleTheme.muted.opacity(0.14) : .clear)
            .overlay(Rectangle().strokeBorder(JSConsoleTheme.muted.opacity(0.3), lineWidth: 0.5))
    }
}

/// The frames behind a console call — a thrown exception's, or any row whose
/// source label the reader clicked. Metro's resolved frames when it answered;
/// the raw bundle coordinates otherwise, so a stack is never simply missing.
/// Library frames read dimmer, the way Chrome greys its ignore-listed ones.
struct StackView: View {
    let stack: CDPStackTrace
    var symbolicated: [SymbolicatedFrame] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if symbolicated.isEmpty {
                ForEach(stack.callFrames.prefix(8)) { frame in
                    frameText(frame.display, dim: false)
                }
            } else {
                ForEach(symbolicated.prefix(8)) { frame in
                    frameText(frame.display, dim: frame.isLibrary)
                }
            }
        }
        .padding(.leading, 4)
    }

    private func frameText(_ text: String, dim: Bool) -> some View {
        Text(text)
            .font(.app(.caption2).monospaced())
            .foregroundStyle(JSConsoleTheme.muted.opacity(dim ? 0.55 : 1))
            .textSelection(.enabled)
    }
}
