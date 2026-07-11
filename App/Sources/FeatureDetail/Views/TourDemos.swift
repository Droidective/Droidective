import ADBKit
import SwiftUI

// The onboarding tour's animated demos: small looping SwiftUI scenes that show
// each concept in motion (gif-style) instead of describing it. Drawn, not
// recorded, so they stay crisp at any scale, follow the theme, and add no
// binary assets. With Reduce Motion on, each demo freezes on its most
// composed frame.

/// Cycles `phase` through `0..<phases` on `interval`, animating each change.
struct TourDemoLoop<Content: View>: View {
    let phases: Int
    var interval: Duration = .seconds(1.7)
    @ViewBuilder var content: (Int) -> Content
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(reduceMotion ? phases - 1 : phase)
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(duration: 0.55)) { phase = (phase + 1) % phases }
                }
            }
    }
}

/// The framed stage every demo renders on. A nil height (the default) lets
/// the stage flex to fill the page instead of leaving dead space.
struct TourDemoCanvas<Content: View>: View {
    var height: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: height)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Shared bits

private struct DemoRow: View {
    let icon: String
    let title: String
    var highlighted = false
    var pinned = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.app(size: 11))
                .foregroundStyle(highlighted ? Color.brandAccent : .secondary)
                .frame(width: 15)
            Text(title)
                .font(.app(size: 11, weight: highlighted ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.app(size: 8))
                    .foregroundStyle(.brandAccent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            highlighted ? Color.brandAccent.opacity(0.14) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

private struct DemoKeycap: View {
    let label: String
    var pressed = false

    var body: some View {
        Text(label)
            .font(.app(size: 15, weight: .semibold, design: .rounded))
            .frame(minWidth: 34)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.bgRoot, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(pressed ? Color.brandAccent : Color.borderSubtle, lineWidth: pressed ? 1.5 : 1)
            )
            .scaleEffect(pressed ? 0.92 : 1)
            .shadow(color: .black.opacity(pressed ? 0 : 0.18), radius: 1.5, y: 1.5)
    }
}

private struct DemoChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.app(size: 10))
            Text(title).font(.app(size: 10, weight: .medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.brandAccent.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.brandAccent.opacity(0.35), lineWidth: 1))
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

// MARK: - 1. Sidebar

/// Highlight a feature → pin it (it moves into the Pinned section) → search
/// filters the list.
struct SidebarTourDemo: View {
    var body: some View {
        TourDemoCanvas {
            TourDemoLoop(phases: 4) { phase in
                HStack(spacing: 0) {
                    sidebar(phase: phase)
                        .frame(width: 190)
                        .background(Color.bgRoot.opacity(0.55))
                    Divider()
                    detail(phase: phase)
                }
            }
        }
    }

    @ViewBuilder private func sidebar(phase: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.app(size: 10)).foregroundStyle(.tertiary)
                Text(phase == 3 ? "log" : "Search features…")
                    .font(.app(size: 10))
                    .foregroundStyle(phase == 3 ? .primary : .tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderSubtle))
            .padding(.bottom, 4)

            if phase >= 2 {
                Text("PINNED")
                    .font(.app(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
                DemoRow(icon: "camera.viewfinder", title: "Screenshot", highlighted: true, pinned: true)
            }

            Text("LOGS & DIAGNOSTICS")
                .font(.app(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
                .padding(.top, 2)
            DemoRow(icon: "doc.text.below.ecg", title: "Logcat", highlighted: phase == 3)
            if phase < 2 {
                DemoRow(icon: "camera.viewfinder", title: "Screenshot", highlighted: phase == 1, pinned: phase == 1)
            }
            if phase != 3 {
                DemoRow(icon: "square.grid.2x2", title: "Apps")
                DemoRow(icon: "antenna.radiowaves.left.and.right", title: "Reactotron")
                DemoRow(icon: "wifi", title: "Wi-Fi")
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    @ViewBuilder private func detail(phase: Int) -> some View {
        VStack(spacing: 10) {
            Image(systemName: phase >= 1 ? "camera.viewfinder" : "doc.text.below.ecg")
                .font(.app(size: 34))
                .foregroundStyle(.brandAccent)
                .symbolRenderingMode(.hierarchical)
            Text(phase == 0 ? "Every tool, one click away" : phase == 3 ? "…or search and hit ⏎" : "Right-click to pin favorites")
                .font(.app(size: 11))
                .foregroundStyle(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 2. Tabs & split

/// One tab → a second opens → the pane splits side-by-side.
struct TabsSplitTourDemo: View {
    var body: some View {
        TourDemoCanvas {
            TourDemoLoop(phases: 3) { phase in
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        tab("doc.text.below.ecg", "Logcat", active: phase != 1)
                        if phase >= 1 {
                            tab("antenna.radiowaves.left.and.right", "Reactotron", active: phase == 1)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                        Image(systemName: "plus")
                            .font(.app(size: 10, weight: .semibold))
                            .foregroundStyle(phase == 0 ? AnyShapeStyle(.brandAccent) : AnyShapeStyle(.tertiary))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.bgRoot.opacity(0.55))
                    Divider()
                    if phase < 2 {
                        pane(phase == 1 ? "antenna.radiowaves.left.and.right" : "doc.text.below.ecg",
                             phase == 1 ? "Reactotron" : "Logcat")
                    } else {
                        HStack(spacing: 0) {
                            pane("doc.text.below.ecg", "Logcat")
                            Divider()
                            pane("antenna.radiowaves.left.and.right", "Reactotron")
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }

    private func tab(_ icon: String, _ title: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.app(size: 9))
            Text(title).font(.app(size: 10, weight: .medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(active ? Color.brandAccent.opacity(0.16) : .clear, in: Capsule())
        .foregroundStyle(active ? Color.brandAccent : .secondary)
    }

    private func pane(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.app(size: 26))
                .foregroundStyle(.brandAccent)
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.app(size: 11)).foregroundStyle(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 3. Roles

/// Cycle three roles; the featured tool chips swap with each one.
struct RolesTourDemo: View {
    private static let roles: [(role: UserRole, chips: [(String, String)])] = [
        (.reactNativeDeveloper, [
            ("antenna.radiowaves.left.and.right", "Reactotron"),
            ("chevron.left.forwardslash.chevron.right", "JS Console"),
            ("arrow.clockwise", "Reload JS"),
        ]),
        (.qaTester, [
            ("camera.viewfinder", "Screenshot"),
            ("record.circle", "Screen Record"),
            ("exclamationmark.triangle", "Crash Catcher"),
        ]),
        (.androidDeveloper, [
            ("doc.text.below.ecg", "Logcat"),
            ("folder", "File Explorer"),
            ("link", "Deep Link"),
        ]),
    ]

    var body: some View {
        TourDemoCanvas {
            TourDemoLoop(phases: Self.roles.count) { phase in
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        ForEach(Self.roles.indices, id: \.self) { index in
                            card(Self.roles[index].role, selected: index == phase)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(Self.roles[phase].chips, id: \.1) { chip in
                            DemoChip(icon: chip.0, title: chip.1)
                        }
                    }
                    .id(phase)
                }
                .padding(18)
            }
        }
    }

    private func card(_ role: UserRole, selected: Bool) -> some View {
        VStack(spacing: 7) {
            Image(systemName: role.icon)
                .font(.app(size: 19))
                .foregroundStyle(selected ? Color.brandAccent : .secondary)
            Text(role.label)
                .font(.app(size: 10, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(width: 118, height: 84)
        .background(Color.bgRoot.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Color.brandAccent : Color.borderSubtle, lineWidth: selected ? 1.5 : 1)
        )
        .scaleEffect(selected ? 1.04 : 1)
    }
}

// MARK: - 4. Settings & hotkeys

/// Settings sections on the left; a per-feature hotkey "presses" on the right.
struct SettingsHotkeysTourDemo: View {
    private static let sections: [(String, String)] = [
        ("gearshape", "General"),
        ("paintbrush", "Appearance"),
        ("keyboard", "Hotkeys"),
        ("stethoscope", "Doctor"),
    ]

    var body: some View {
        TourDemoCanvas {
            TourDemoLoop(phases: 3) { phase in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Self.sections.indices, id: \.self) { index in
                            DemoRow(
                                icon: Self.sections[index].0,
                                title: Self.sections[index].1,
                                highlighted: (phase == 0 && index == 3) || (phase >= 1 && index == 2)
                            )
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(width: 160)
                    .background(Color.bgRoot.opacity(0.55))
                    Divider()
                    VStack(spacing: 14) {
                        if phase == 0 {
                            VStack(spacing: 8) {
                                Image(systemName: "stethoscope")
                                    .font(.app(size: 26))
                                    .foregroundStyle(.brandAccent)
                                Text("The Doctor checks adb & your toolchain")
                                    .font(.app(size: 11))
                                    .foregroundStyle(.textMuted)
                            }
                        } else {
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.viewfinder").font(.app(size: 12))
                                    Text("Screenshot").font(.app(size: 12, weight: .medium))
                                    Spacer(minLength: 18)
                                    HStack(spacing: 4) {
                                        DemoKeycap(label: "⇧", pressed: phase == 2)
                                        DemoKeycap(label: "⌘", pressed: phase == 2)
                                        DemoKeycap(label: "S", pressed: phase == 2)
                                    }
                                }
                                .padding(.horizontal, 14)
                                Text(phase == 2 ? "Pressed anywhere — even with the window closed" : "Every feature can have a global hotkey")
                                    .font(.app(size: 11))
                                    .foregroundStyle(.textMuted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - 5. Quick Actions

/// ⇧⌘Space presses → the floating panel pops over a dimmed desktop.
struct QuickActionsTourDemo: View {
    var height: CGFloat?

    private static let tiles: [(String, String)] = [
        ("camera.viewfinder", "Screenshot"), ("arrow.clockwise", "Reload JS"),
        ("moon", "Dark Mode"), ("square.grid.2x2", "Apps"),
        ("play.rectangle", "Emulators"), ("arrow.down.app", "Install APK"),
    ]

    var body: some View {
        TourDemoCanvas(height: height) {
            TourDemoLoop(phases: 3) { phase in
                ZStack {
                    HStack(spacing: 6) {
                        DemoKeycap(label: "⇧", pressed: phase == 1)
                        DemoKeycap(label: "⌘", pressed: phase == 1)
                        DemoKeycap(label: "Space", pressed: phase == 1)
                    }
                    .opacity(phase == 2 ? 0.15 : 1)
                    if phase == 2 {
                        panel
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.app(size: 10)).foregroundStyle(.tertiary)
                Text("Type to run anything…").font(.app(size: 10)).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.bgRoot, in: RoundedRectangle(cornerRadius: 6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(Self.tiles, id: \.1) { tile in
                    VStack(spacing: 5) {
                        Image(systemName: tile.0).font(.app(size: 13)).foregroundStyle(.brandAccent)
                        Text(tile.1).font(.app(size: 9)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.bgRoot.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(10)
        .frame(width: 300)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.borderSubtle))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
    }
}
