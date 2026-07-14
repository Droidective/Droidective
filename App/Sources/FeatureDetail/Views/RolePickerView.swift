import ADBKit
import SwiftUI

/// First-launch full-window takeover: the user picks a role and gets a focused
/// set of features instead of all of them — the answer to "this app is
/// overwhelming". Skippable ("Show me everything") and changeable later from
/// Settings. Selecting a role seeds the curated set via `AppState.chooseRole`.
///
/// Presented as a full-bleed overlay (not a sheet) so it genuinely takes over
/// the window; macOS has no `fullScreenCover`.
struct RolePickerView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasChosenRole") private var hasChosenRole = false
    @State private var appeared = false

    private let columns = [GridItem(.adaptive(minimum: 236), spacing: 14)]

    var body: some View {
        VStack(spacing: 26) {
            header
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(UserRole.allCases.enumerated()), id: \.element) { index, role in
                    RoleCard(role: role) { choose(role) }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(
                            reduceMotion ? nil : .spring(duration: 0.35).delay(Double(index) * 0.04),
                            value: appeared
                        )
                }
            }
            .frame(maxWidth: 790)
            skipButton
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bgRoot)
        .overlay(alignment: .topTrailing) { closeButton }
        .onAppear { appeared = true }
    }

    /// Re-opened from Home ("Change role"), the picker must be escapable
    /// without re-picking: choosing any role — even the current one — re-seeds
    /// the curated set and resets every open tab. Hidden on first run, where
    /// picking (or "show me everything") is the only sensible exit.
    @ViewBuilder private var closeButton: some View {
        if hasChosenRole {
            Button {
                state.presentRolePicker = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.app(size: 22))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(18)
            .help("Close without changing your role")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.app(size: 38))
                .foregroundStyle(.brandAccent)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 2)
            Text("Welcome to Droidective".uppercased())
                .font(.app(.caption).weight(.semibold))
                .kerning(1.2)
                .foregroundStyle(.brandAccent)
            Text("What do you do?")
                .font(.app(.largeTitle).bold())
                .foregroundStyle(.textMain)
            Text("Pick a role and we'll start you with the tools you'll use most. "
                + "Everything else is one click away — and you can change this anytime.")
                .font(.app(.body))
                .foregroundStyle(.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Deliberately quiet next to the cards (one primary action per screen),
    /// but with a real hit area and the concrete outcome in the label.
    private var skipButton: some View {
        Button {
            choose(nil)
        } label: {
            Label(
                "Show me everything — all \(FeatureRegistry.catalogFeatureIDs.count) tools",
                systemImage: "square.grid.3x3"
            )
            .font(.app(.callout))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverUnderlineButtonStyle())
    }

    private func choose(_ role: UserRole?) {
        hasChosenRole = true
        state.chooseRole(role)
    }
}

/// One selectable role tile: icon + tool count up top, name, one-line blurb,
/// and a preview row of the first tools the role actually seeds — the card
/// answers "what do I get?", not just "what am I?". Hover lifts, press
/// scales, and keyboard focus draws the same accent ring, so every input
/// method sees a distinct state.
private struct RoleCard: View {
    let role: UserRole
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var curated: [String] { FeatureRegistry.featuresByRole[role] ?? [] }

    private var previewFeatures: [FeatureDef] {
        // Presented for the card's role, so the iOS card previews
        // "Simulators" while the Android-first cards preview "Emulators".
        curated.prefix(2).compactMap { FeatureRegistry.byID[$0] }
            .map { FeatureRegistry.presented($0, for: role) }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    Image(systemName: role.icon)
                        .font(.app(size: 19, weight: .medium))
                        .foregroundStyle(.brandAccent)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 38, height: 38)
                        .background(
                            Color.brandAccent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    Spacer(minLength: 8)
                    Text("\(curated.count) tools")
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.bgRoot, in: Capsule())
                }
                Text(role.label)
                    .font(.app(.title3).weight(.semibold))
                    .foregroundStyle(.textMain)
                Text(role.blurb)
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                previewRow
            }
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .padding(16)
            .background(.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        hovering || focused ? Color.brandAccent : Color.borderSubtle,
                        lineWidth: hovering || focused ? 2 : 1
                    )
            }
            .shadow(
                color: .black.opacity(hovering ? 0.16 : 0.05),
                radius: hovering ? 9 : 3,
                y: hovering ? 4 : 1
            )
            .scaleEffect(hovering && !reduceMotion ? 1.015 : 1)
        }
        .buttonStyle(PressableCardButtonStyle())
        .focused($focused)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .accessibilityHint("Sets up the sidebar with \(curated.count) tools for this role")
    }

    /// The first curated tools as small chips, ending in "+N" — the concrete
    /// preview of what picking this card does.
    private var previewRow: some View {
        HStack(spacing: 6) {
            ForEach(previewFeatures) { feature in
                Label(feature.title, systemImage: feature.icon)
                    .font(.app(.caption))
                    .lineLimit(1)
                    .foregroundStyle(.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.bgRoot, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
            }
            if curated.count > previewFeatures.count {
                Text("+\(curated.count - previewFeatures.count)")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
            }
        }
    }
}

/// Press feedback for the role cards: a quick, interruptible scale-down —
/// enough to read as a press without shifting the grid.
private struct PressableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet secondary action: muted at rest, brightens on hover — subordinate to
/// the cards without becoming an untargetable text sliver.
private struct HoverUnderlineButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? Color.textMain : Color.textMuted)
            .background(
                hovering ? Color.textMain.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
