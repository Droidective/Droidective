import ADBKit
import AppKit
import SwiftUI

/// Columns the wall lays out with: 0 = auto (derived from the pane width),
/// otherwise the user's explicit choice. App-wide, like the terminal's tab
/// placement — it's a way of looking at things, not a property of one window.
let mirrorWallColumnsKey = "mirrorWallColumns"

/// The Mirror Wall: up to `MirrorWall.maximumDevices` devices mirrored side by
/// side in one pane, each interactive, each on its own scrcpy session.
///
/// The wall picks its own devices (the header's Devices menu) rather than
/// following the device bar — the bar selects *one* device and every other
/// feature is scoped to it. Tiles drag to rearrange, and any tile can be broken
/// out into its own window.
struct MirrorWallView: View {
    @Environment(AppState.self) private var state
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.openWindow) private var openWindow
    @AppStorage(mirrorWallColumnsKey) private var manualColumns = 0
    @State private var wall: MirrorWallModel?
    /// Delayed teardown for a hidden wall; cancelled if the tab returns in time.
    @State private var teardownTask: Task<Void, Never>?
    @State private var dragging: String?
    @State private var dropSlot: DropSlot?
    @State private var pendingScreenshot: NSImage?
    @State private var editingScreenshot: NSImage?

    /// Where a dragged tile would land: before a serial, or at the end.
    enum DropSlot: Equatable {
        case before(String)
        case end
    }

    var body: some View {
        ZStack {
            if let editingScreenshot {
                ScreenshotEditorView(image: editingScreenshot) { self.editingScreenshot = nil }
            } else {
                wallContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .imageDecision(image: $pendingScreenshot) { editingScreenshot = $0 }
        .task {
            if wall == nil {
                wall = MirrorWallModel(
                    adb: state.env.engine.client, locator: state.env.engine.locator)
            }
            sync()
        }
        .onChange(of: selection) { syncSelection() }
        .onChange(of: connectedSerials) { syncSelection() }
        .onChange(of: blockedSerials) { sync() }
        .onChange(of: tabIsActive) { _, active in
            if active {
                teardownTask?.cancel()
                teardownTask = nil
                sync()
            } else {
                scheduleHiddenTeardown()
            }
        }
        .onChange(of: wall?.liveSerials) { _, live in
            state.noteMirrorClaims(live ?? [], featureID: "mirror-wall")
        }
        .onDisappear {
            teardownTask?.cancel()
            wall?.shutDown()
            state.noteMirrorClaims([], featureID: "mirror-wall")
        }
    }

    @ViewBuilder private var wallContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if connectedDevices.isEmpty {
                ContentUnavailableView(
                    "Connect devices to mirror",
                    systemImage: "square.grid.2x2",
                    description: Text("Plug in or pair Android devices, then pick up to "
                        + "\(MirrorWall.maximumDevices) to watch side by side."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selection.isEmpty {
                ContentUnavailableView(
                    "No devices picked",
                    systemImage: "square.grid.2x2",
                    description: Text("Choose the devices this wall shows from the Devices menu."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let wall {
                grid(wall: wall)
            }
        }
        .background(.bgRoot)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            devicesMenu

            Text("\(selection.count) of \(MirrorWall.maximumDevices)")
                .font(.app(.caption))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            layoutMenu
            fullViewButton
            optionsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var devicesMenu: some View {
        Menu {
            ForEach(connectedDevices) { device in
                Toggle(state.deviceDisplayName(device), isOn: selectionBinding(device.serial))
                    // At the cap, only the already-picked boxes still work —
                    // adding a seventh device would be a seventh encoder.
                    .disabled(!selection.contains(device.serial)
                        && !MirrorWall.canAdd(to: selection))
            }
        } label: {
            Label("Devices", systemImage: "checklist")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Pick which devices this wall shows")
    }

    /// Give the wall the whole display: the app's chrome (sidebar, device bar,
    /// tab strip) goes away and the window enters macOS full screen. This row
    /// stays — it's the wall's own controls, and the way back out.
    private var fullViewButton: some View {
        Button {
            state.toggleFullView()
        } label: {
            Image(systemName: state.fullView
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
                .font(.app(.body))
        }
        .buttonStyle(.plain)
        .help(state.fullView
            ? "Exit full view (⇧⌘F)"
            : "Full view — hide the app chrome (⇧⌘F)")
    }

    private var layoutMenu: some View {
        Menu {
            Picker("Columns", selection: $manualColumns) {
                Text("Auto").tag(0)
                Text("1 Column").tag(1)
                Text("2 Columns").tag(2)
                Text("3 Columns").tag(3)
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                manualColumns == 0 ? "Auto" : "\(manualColumns) ×",
                systemImage: "rectangle.split.3x1")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Arrange the tiles automatically, or in a fixed number of columns")
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Audio from the Focused Device", isOn: Binding(
                get: { wall?.audioOnFocused ?? false },
                set: { wall?.setAudioOnFocused($0) }))

            Divider()

            Button("Open Each in Its Own Window") { popOutAll() }
                .disabled(selection.isEmpty)
            Button("Arrange Mirror Windows") { state.core.arrangeMirrorWindows() }
                .disabled(!state.core.hasMirrorWindows)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.app(.title3))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Audio, and breaking tiles out into windows")
    }

    // MARK: - Grid

    private func grid(wall: MirrorWallModel) -> some View {
        GeometryReader { geometry in
            let columnCount = columnCount(paneWidth: geometry.size.width)
            let tileWidth = tileWidth(paneWidth: geometry.size.width, columns: columnCount)
            ScrollView {
                LazyVGrid(columns: gridItems(columnCount), spacing: 10) {
                    ForEach(selection, id: \.self) { serial in
                        if let device = connectedDevices.first(where: { $0.serial == serial }) {
                            tile(device: device, wall: wall, width: tileWidth)
                                .frame(height: tileHeight(
                                    paneHeight: geometry.size.height,
                                    tiles: selection.count,
                                    columns: columnCount))
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    private func tile(device: Device, wall: MirrorWallModel, width: Double) -> some View {
        MirrorWallTile(
            device: device,
            wall: wall,
            blocked: blocked(device.serial),
            dropEdge: dropEdge(device.serial),
            dragItem: {
                dragging = device.serial
                return privateDragItem(.mirrorWallTile, device.serial)
            },
            onScreenshot: { capture(device.serial, wall: wall) },
            onPopOut: { popOut(device.serial) },
            onBringBack: { state.core.closeMirrorWindow(device.serial) },
            onOpenFullMirror: { openFullMirror(device.serial) })
            .onDrop(of: [.mirrorWallTile], delegate: MirrorWallDrop(
                target: device.serial,
                dragging: dragging,
                isLast: selection.last == device.serial,
                tileWidth: width,
                setSlot: { dropSlot = $0 },
                perform: moveTile))
    }

    private func dropEdge(_ serial: String) -> MirrorWallTile.DropEdge? {
        switch dropSlot {
        case .before(serial): .leading
        case .end where selection.last == serial: .trailing
        default: nil
        }
    }

    private func gridItems(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: max(count, 1))
    }

    private func columnCount(paneWidth: Double) -> Int {
        guard manualColumns == 0 else {
            return MirrorWall.columns(manual: manualColumns, tiles: selection.count)
        }
        return MirrorWall.columns(paneWidth: paneWidth, tiles: selection.count)
    }

    private func tileWidth(paneWidth: Double, columns: Int) -> Double {
        let usable = paneWidth - 20 - Double(max(columns - 1, 0)) * 10
        return max(usable / Double(max(columns, 1)), 1)
    }

    /// Fill the pane: rows share its height so a picked set is all visible at
    /// once, which is the point of a wall. A pane too short for that scrolls
    /// rather than shrinking tiles into uselessness.
    private func tileHeight(paneHeight: Double, tiles: Int, columns: Int) -> Double {
        let rows = max(Int((Double(tiles) / Double(max(columns, 1))).rounded(.up)), 1)
        let usable = paneHeight - 20 - Double(rows - 1) * 10
        return max(usable / Double(rows), 180)
    }

    // MARK: - Devices & selection

    private var connectedDevices: [Device] {
        state.devices.filter { $0.isReady && $0.platform == .android }
    }

    private var connectedSerials: [String] { connectedDevices.map(\.serial) }

    /// The picked devices, in tile order, minus any that left. Never picked
    /// (nil) opens on what's connected; an explicitly emptied wall stays empty.
    private var selection: [String] {
        MirrorWall.reconciled(selection: state.mirrorWallSerials, connected: connectedSerials)
    }

    private var blockedSerials: Set<String> {
        Set(selection.filter { blocked($0) != nil })
    }

    /// Why this device can't stream in the wall right now. Every route to the
    /// live mirror drives one device-side encoder, so a device already mirrored
    /// — in its own pop-out window, or in another workspace window — shows that
    /// rather than starting a second session on it.
    private func blocked(_ serial: String) -> MirrorWallTile.Blocked? {
        if state.core.mirrorWindowSerials.contains(serial) { return .poppedOut }
        // This window's *own* Mirror Screen tab counts too — a split pane shows
        // the wall and that tab at once — and the registry's conflict queries
        // exclude the window doing the asking, so the wall checks for it by
        // hand. `claimant` answers for live sessions only, so a mirror tab
        // sitting hidden and torn down doesn't hold a device hostage.
        if let owner = state.core.registry.claimant(ofFeature: "scrcpy", on: serial) {
            return owner == state.id ? .mirrorTab : .otherWindow(owner)
        }
        guard let owner = state.core.registry.owner(ofMirroredDevice: serial, excluding: state.id)
        else { return nil }
        return .otherWindow(owner)
    }

    private func selectionBinding(_ serial: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(serial) },
            // Writing the toggled *reconciled* list is what turns "never
            // picked" into an explicit choice, so the first uncheck sticks
            // instead of being refilled from the connected devices.
            set: { _ in state.mirrorWallSerials = MirrorWall.toggled(serial, in: selection) })
    }

    private func moveTile(_ serial: String, to slot: DropSlot) {
        let order = switch slot {
        case let .before(target): SidebarOrdering.move(serial, before: target, in: selection)
        case .end: SidebarOrdering.moveToEnd(serial, in: selection)
        }
        state.mirrorWallSerials = order
        dragging = nil
        dropSlot = nil
    }

    // MARK: - Lifecycle

    private func sync() {
        guard tabIsActive else { return }
        wall?.sync(order: selection, blocked: blockedSerials)
    }

    /// A device leaving is written back, so the stored wall matches what's on
    /// screen — the picked set is the user's, and it shouldn't quietly carry
    /// serials no tile shows.
    private func syncSelection() {
        let reconciled = selection
        if state.mirrorWallSerials != nil, state.mirrorWallSerials != reconciled {
            state.mirrorWallSerials = reconciled
        }
        sync()
    }

    /// Stop every tile once the wall has been hidden for the grace window — six
    /// encoders behind another tab is worth reclaiming, and a quick tab flip
    /// still resumes in place. Same window the single mirror uses.
    private func scheduleHiddenTeardown() {
        teardownTask?.cancel()
        teardownTask = Task {
            try? await Task.sleep(for: .seconds(mirrorHiddenGraceSeconds))
            guard !Task.isCancelled else { return }
            teardownTask = nil
            wall?.suspend()
        }
    }

    // MARK: - Actions

    private func capture(_ serial: String, wall: MirrorWallModel) {
        Task {
            guard let image = await wall.captureScreenshot(serial) else { return }
            pendingScreenshot = image
        }
    }

    /// Break one tile out into its own window. The wall keeps its slot: the
    /// tile shows "Mirroring in …" (the window claims the device) and takes it
    /// back when the window closes.
    private func popOut(_ serial: String) {
        state.core.mirrorWindowOwner = state.id
        openWindow(id: MirrorWindow.windowID, value: serial)
    }

    private func popOutAll() {
        for serial in selection { popOut(serial) }
    }

    /// Hand this device to the full Mirror Screen tab — the screen with the
    /// nav bar, recording and the audio sheet.
    private func openFullMirror(_ serial: String) {
        state.requestDevice(serial, force: true)
        if let feature = FeatureRegistry.byID["scrcpy"] { state.openFeature(feature) }
    }
}

/// Drop target for one tile: the left half inserts before it, the right half
/// after — and the last tile's right half is how a tile reaches the end, the
/// one slot an insertion line before a tile can't express.
private struct MirrorWallDrop: DropDelegate {
    let target: String
    let dragging: String?
    let isLast: Bool
    let tileWidth: Double
    let setSlot: (MirrorWallView.DropSlot?) -> Void
    let perform: (String, MirrorWallView.DropSlot) -> Void

    func validateDrop(info: DropInfo) -> Bool { slot(info) != nil }

    func dropEntered(info: DropInfo) { setSlot(slot(info)) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let here = slot(info)
        setSlot(here)
        return here == nil ? nil : DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { setSlot(nil) }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragging, let slot = slot(info) else { return false }
        perform(dragging, slot)
        return true
    }

    private func slot(_ info: DropInfo) -> MirrorWallView.DropSlot? {
        guard let dragging, dragging != target else { return nil }
        if isLast, tileWidth > 0, info.location.x > tileWidth / 2 { return .end }
        return .before(target)
    }
}
