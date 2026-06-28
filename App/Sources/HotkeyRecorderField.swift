import AppKit
import KeyboardShortcuts
import SwiftUI

/// Process-wide recording state so only one field records at a time (starting a
/// second cancels the first) and the captured combo lands on the right field.
/// `@Observable`, so fields reflect the held modifiers live.
@MainActor @Observable final class HotkeyRecording {
    static let shared = HotkeyRecording()
    private init() {}

    private(set) var active: KeyboardShortcuts.Name?
    private(set) var held = NSEvent.ModifierFlags()
    private var monitor: Any?

    func start(_ name: KeyboardShortcuts.Name) {
        stop()
        active = name
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        active = nil
        held = []
    }

    /// Returns nil to swallow the event while recording so it can't fire an app
    /// shortcut; returns the event to let it pass otherwise.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let name = active else { return event }
        switch event.type {
        case .flagsChanged:
            held = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return nil
        case .keyDown:
            switch event.keyCode {
            case 53:  // Esc — cancel without changing the shortcut
                stop()
            case 51:  // Delete — clear the shortcut
                KeyboardShortcuts.setShortcut(nil, for: name)
                stop()
            default:
                // Require ⌘/⌥/⌃ so a global hotkey can't be a bare key that fires
                // on every press.
                let mods = event.modifierFlags.intersection([.command, .option, .control])
                if !mods.isEmpty, let shortcut = KeyboardShortcuts.Shortcut(event: event) {
                    KeyboardShortcuts.setShortcut(shortcut, for: name)
                    stop()
                }
            }
            return nil
        default:
            return event
        }
    }

    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols
    }
}

/// A keyboard-shortcut recorder with live feedback: it shows the modifiers as
/// you hold them (⌃⌘…) and captures the full combo on the first non-modifier
/// key, writing it through `KeyboardShortcuts` so it stays in sync with the
/// global registration and the Hotkeys settings. `autoFocus` begins recording
/// the moment it appears (the sidebar's Set-Hotkey popover uses that).
struct HotkeyRecorderField: View {
    let name: KeyboardShortcuts.Name
    var autoFocus = false

    @State private var current: KeyboardShortcuts.Shortcut?

    private var recording: Bool { HotkeyRecording.shared.active == name }

    var body: some View {
        HStack(spacing: 6) {
            Button { toggle() } label: {
                Text(label)
                    .foregroundStyle(recording || current != nil ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        if recording {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.tint, lineWidth: 2)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if current != nil, !recording {
                Button { clear() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onAppear {
            current = KeyboardShortcuts.getShortcut(for: name)
            if autoFocus { HotkeyRecording.shared.start(name) }
        }
        .onDisappear {
            if recording { HotkeyRecording.shared.stop() }
            current = KeyboardShortcuts.getShortcut(for: name)
        }
        .onChange(of: recording) { _, isRecording in
            if !isRecording { current = KeyboardShortcuts.getShortcut(for: name) }
        }
    }

    private var label: String {
        if recording {
            let symbols = HotkeyRecording.modifierSymbols(HotkeyRecording.shared.held)
            return symbols.isEmpty ? "Press your shortcut…" : "\(symbols)…"
        }
        return current?.description ?? "Click to record"
    }

    private func toggle() {
        if recording {
            HotkeyRecording.shared.stop()
        } else {
            HotkeyRecording.shared.start(name)
        }
    }

    private func clear() {
        KeyboardShortcuts.setShortcut(nil, for: name)
        current = nil
    }
}
