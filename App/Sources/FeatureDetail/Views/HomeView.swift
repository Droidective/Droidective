import ADBKit
import AppKit
import SwiftUI

/// The landing screen, now a role-aware launchpad: an inline feature search, a
/// strip of the features used most, the pinned features, a grid of the user's
/// curated tools in the same order as the sidebar, an expandable "More
/// features" section to add the rest, the keyboard shortcuts that drive the
/// app, and the no-device onboarding when nothing is connected.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var showMore = false
    @State private var query = ""

    private static let welcomeTitle = "Welcome to Droidective"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                searchBar
                if !query.isEmpty {
                    searchResultsSection
                } else {
                    if state.devices.isEmpty {
                        connectCard
                    }
                    frequentSection
                    pinnedSection
                    launchpadSection
                    moreFeaturesSection
                    shortcutsSection
                    tourFooter
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search

    /// The shared, tested palette ranking — the same order ⌘T shows — capped
    /// to a grid's worth of results.
    private var searchMatches: [FeatureDef] {
        Array(
            PaletteSearch.features(
                query: query,
                enabled: state.layout.effectiveEnabledIDs,
                favorites: state.layout.favorites
            ).prefix(12)
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.textMuted)
            TextField("Search features…", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { openTopMatch() }
            if query.isEmpty {
                KeyHint("⌘T")
            } else {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.textMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .font(.app(.title3))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .onExitCommand { query = "" }
    }

    @ViewBuilder private var searchResultsSection: some View {
        let matches = searchMatches
        if matches.isEmpty {
            Text("No matching features")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(matches) { feature in
                    FeatureCard(feature: feature) { open(feature) }
                }
            }
        }
    }

    private func openTopMatch() {
        guard let first = searchMatches.first else { return }
        open(first)
    }

    private func open(_ feature: FeatureDef) {
        query = ""
        state.openFeature(feature)
    }

    // MARK: - Frequently used

    @ViewBuilder private var frequentSection: some View {
        let frequent = state.frequentFeatures
        if !frequent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Frequently used")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(frequent) { feature in
                        FrequentPill(feature: feature) { state.openFeature(feature) }
                    }
                }
            }
        }
    }

    // MARK: - Header

    /// Responsive so a narrow detail pane (e.g. sidebar + notifications panel
    /// open on a small window) never starves the title into per-character
    /// wrapping. `ViewThatFits` keeps the role badge inline when there's room
    /// and wraps it below the title when there isn't; the title scales rather
    /// than breaking mid-word at the extreme. The subtitle always sits on its
    /// own full-width line so it wraps cleanly and doesn't skew the fit.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    logo
                    Text(Self.welcomeTitle)
                        .font(.app(.largeTitle).bold())
                        .fixedSize()
                    Spacer(minLength: 12)
                    roleBadge
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        logo
                        Text(Self.welcomeTitle)
                            .font(.app(.largeTitle).bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    roleBadge
                }
            }
            Text("An Android & React Native debugging command palette, driven over adb.")
                .font(.app(.title3))
                .foregroundStyle(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logo: some View {
        Image("AppLogoLight")
            .resizable()
            .frame(width: 60, height: 60)
    }

    /// Current role as a pill that opens the picker — the "change this anytime"
    /// affordance the first-run picker promises.
    private var roleBadge: some View {
        Button { state.presentRolePicker = true } label: {
            HStack(spacing: 6) {
                Image(systemName: state.selectedRole?.icon ?? "square.grid.2x2")
                Text(state.selectedRole?.label ?? "All features")
                Image(systemName: "chevron.down")
                    .font(.app(.caption2))
                    .foregroundStyle(.textMuted)
            }
            .font(.app(.callout))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.bgSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Your role decides which tools start here — change it anytime")
    }

    // MARK: - Pinned

    /// The sidebar's Pinned section, mirrored on Home in the same order.
    @ViewBuilder private var pinnedSection: some View {
        let pinned = state.pinnedFeatures
        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Pinned")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(pinned) { feature in
                        FeatureCard(feature: feature) { state.openFeature(feature) }
                    }
                }
            }
        }
    }

    // MARK: - Launchpad

    private var launchpadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Your tools")
            Text("Everything on your sidebar, in the same order. Add more below or from the sidebar.")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(state.launchpadFeatures) { feature in
                    FeatureCard(feature: feature) { state.openFeature(feature) }
                }
            }
        }
    }

    // MARK: - More features

    /// Catalog features the user hasn't enabled yet — the "show me other
    /// features so I can pick" path, addable in one click. System features are
    /// always on, so they never appear here.
    private var addableFeatures: [FeatureDef] {
        let enabled = Set(state.enabledFeatures.map(\.id))
        let catalog = Set(FeatureRegistry.catalogFeatureIDs)
        return state.orderedCategories.flatMap { state.catalogFeatures(in: $0) }
            .filter { catalog.contains($0.id) && !enabled.contains($0.id) && $0.kind != .system }
    }

    @ViewBuilder private var moreFeaturesSection: some View {
        let addable = addableFeatures
        if !addable.isEmpty {
            DisclosureGroup(isExpanded: $showMore) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(addable) { feature in
                        addCard(feature)
                    }
                }
                .padding(.top, 10)
                Button("Manage all features…") { state.requestFeature("catalog") }
                    .buttonStyle(.link)
                    .font(.app(.callout))
                    .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Text("More features")
                        .font(.app(.title2).bold())
                    Text("\(addable.count)")
                        .font(.app(.callout).monospacedDigit())
                        .foregroundStyle(.textMuted)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { showMore.toggle() } }
            }
            .tint(.textMuted)
        }
    }

    private func addCard(_ feature: FeatureDef) -> some View {
        Button { state.setFeatureEnabled(feature.id, enabled: true) } label: {
            HStack(spacing: 10) {
                Image(systemName: feature.icon)
                    .frame(width: 22)
                    .foregroundStyle(.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title).foregroundStyle(.textMain)
                    if let subtitle = feature.subtitle {
                        Text(subtitle)
                            .font(.app(.footnote))
                            .foregroundStyle(.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "plus.circle")
                    .foregroundStyle(.brandAccent)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Add \(feature.title) to your tools")
    }

    // MARK: - Shortcuts

    private struct Shortcut: Identifiable {
        let id = UUID()
        let key: String
        let icon: String
        let title: String
        let detail: String
    }

    private static let shortcuts: [Shortcut] = [
        Shortcut(key: "⌘T", icon: "magnifyingglass", title: "Search features",
                 detail: "Open the palette and jump straight to any feature instantly."),
        Shortcut(key: "⌘B", icon: "sidebar.left", title: "Toggle sidebar",
                 detail: "Hide the feature list for more room, and bring it back anytime."),
        Shortcut(key: "⌘,", icon: "gearshape", title: "Settings",
                 detail: "Theme, startup, hotkeys, and the setup Doctor that checks your toolchain."),
    ]

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Getting around")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Self.shortcuts) { shortcut in
                    shortcutCard(shortcut)
                }
            }
        }
    }

    private func shortcutCard(_ shortcut: Shortcut) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: shortcut.icon)
                .font(.app(.title2))
                .foregroundStyle(.brandAccent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(shortcut.title).font(.app(.headline))
                    KeyHint(shortcut.key)
                }
                Text(shortcut.detail)
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.borderSubtle, lineWidth: 1))
    }

    // MARK: - Connect card (no device)

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No device connected", systemImage: "iphone.gen3.badge.exclamationmark")
                .font(.app(.headline))
            step(1, "On the device, open **Settings → About phone** and tap **Build number** 7 times to enable Developer options.")
            step(2, "In **Developer options**, turn on **USB debugging**.")
            step(3, "Plug in via USB and tap **Allow** on the debugging prompt — or connect over Wi-Fi.")
            HStack(spacing: 10) {
                Button { state.requestFeature("wireless-adb") } label: {
                    Label("Connect wirelessly", systemImage: "wifi")
                }
                Button { state.refreshDevices() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding(.top, 2)
            if state.adbMissing {
                Label("adb isn't installed yet — use the Install button in the device bar first.", systemImage: "exclamationmark.triangle")
                    .font(.app(.footnote))
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.brandAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.app(.callout).weight(.bold))
                .frame(width: 22, height: 22)
                .background(.brandAccent.opacity(0.15), in: Circle())
            Text(.init(text))
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var tourFooter: some View {
        HStack {
            Spacer()
            Button { state.presentTour = true } label: {
                Label("Replay the welcome tour", systemImage: "play.circle")
            }
            .buttonStyle(.link)
            Spacer()
        }
    }

    // MARK: - Building blocks

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.app(.title2).bold())
    }
}

/// One compact pill on the "Frequently used" strip — icon and title only, with
/// the brand hover border. Opens or runs the feature.
private struct FrequentPill: View {
    let feature: FeatureDef
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: feature.icon)
                    .foregroundStyle(.brandAccent)
                Text(feature.title)
                    .foregroundStyle(.textMain)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.app(.callout))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.bgSurface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    hovering ? Color.brandAccent : Color.borderSubtle,
                    lineWidth: hovering ? 2 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .help(feature.subtitle ?? feature.title)
    }
}

/// One tappable tool on the launchpad grid — icon, title, and subtitle, with the
/// brand-green hover border used across the app. Opens or runs the feature.
private struct FeatureCard: View {
    let feature: FeatureDef
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: feature.icon)
                    .font(.app(.title2))
                    .foregroundStyle(.brandAccent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.title)
                        .font(.app(.headline))
                        .foregroundStyle(.textMain)
                    if let subtitle = feature.subtitle {
                        Text(subtitle)
                            .font(.app(.callout))
                            .foregroundStyle(.textMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        hovering ? Color.brandAccent : Color.borderSubtle,
                        lineWidth: hovering ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .help(feature.subtitle ?? feature.title)
    }
}
