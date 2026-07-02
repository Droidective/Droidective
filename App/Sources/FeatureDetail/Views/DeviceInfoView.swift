import ADBKit
import SwiftUI

/// Device properties: an identity header (who is this device), live gauges
/// (memory / storage / battery / apps), curated reference groups, and a full
/// searchable getprop dump behind the filter field.
struct DeviceInfoView: View {
    @Environment(AppState.self) private var state
    @State private var props: [String: String]?
    @State private var overview: DeviceOverview?
    @State private var search = ""

    /// Curated reference groups: (section, [(label, getprop key)]). Identity
    /// facts (brand/model/version) live in the header, not repeated here.
    private static let groups: [(section: String, items: [(label: String, key: String)])] = [
        ("Build & security", [
            ("Android Version", "ro.build.version.release"),
            ("SDK Level", "ro.build.version.sdk"),
            ("Security Patch", "ro.build.version.security_patch"),
            ("Build", "ro.build.display.id"),
            ("Build Type", "ro.build.type"),
        ]),
        ("Hardware", [
            ("Manufacturer", "ro.product.manufacturer"),
            ("Device", "ro.product.device"),
            ("Hardware", "ro.hardware"),
            ("CPU ABI", "ro.product.cpu.abi"),
            ("Supported ABIs", "ro.product.cpu.abilist"),
            ("Display Density", "ro.sf.lcd_density"),
        ]),
        ("Locale & Time", [
            ("Locale", "persist.sys.locale"),
            ("Time Zone", "persist.sys.timezone"),
        ]),
    ]

    var body: some View {
        Group {
            if state.targetSerials.isEmpty {
                ContentUnavailableView(
                    "No device connected", systemImage: "iphone.slash",
                    description: Text("Connect a device to browse its properties.")
                )
            } else if let props {
                content(props)
            } else {
                ProgressView("Reading device info…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: state.targetSerials.first ?? "") { await load() }
    }

    private func content(_ props: [String: String]) -> some View {
        VStack(spacing: 0) {
            TextField("Filter properties…", text: $search)
                .brandField()
                .padding(12)

            Divider()

            if search.isEmpty {
                curated(props)
            } else {
                filtered(props)
            }
        }
    }

    private func curated(_ props: [String: String]) -> some View {
        HubColumn {
            identityHeader(props)
            statsGrid

            ForEach(Self.groups, id: \.section) { group in
                let rows = group.items.compactMap { item -> (String, String)? in
                    guard let value = props[item.key], !value.isEmpty else { return nil }
                    return (item.label, value)
                }
                if !rows.isEmpty {
                    HubSection(group.section) { HubRowList(rows) }
                }
            }

            HubSection("All properties (\(props.count))") {
                Text("Type in the filter box above to search every raw getprop value.")
                    .font(.footnote)
                    .foregroundStyle(.textMuted)
            }
        }
    }

    // MARK: - Identity header

    private func identityHeader(_ props: [String: String]) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.brandAccent.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 26))
                    .foregroundStyle(.brandAccent)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(deviceTitle(props))
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(osLine(props))
                    .font(.callout)
                    .foregroundStyle(.textMuted)
                identityChips(props)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.borderSubtle))
    }

    /// Marketing name when the OEM ships one, else "Brand Model" (without
    /// stuttering when the model already starts with the brand).
    private func deviceTitle(_ props: [String: String]) -> String {
        if let marketing = props["ro.product.marketname"], !marketing.isEmpty { return marketing }
        let brand = (props["ro.product.brand"] ?? "").capitalized
        let model = props["ro.product.model"] ?? "Android device"
        if model.lowercased().hasPrefix(brand.lowercased()) { return model }
        return "\(brand) \(model)".trimmingCharacters(in: .whitespaces)
    }

    private func osLine(_ props: [String: String]) -> String {
        var parts: [String] = []
        if let version = props["ro.build.version.release"], !version.isEmpty { parts.append("Android \(version)") }
        if let sdk = props["ro.build.version.sdk"], !sdk.isEmpty { parts.append("SDK \(sdk)") }
        if let type = props["ro.build.type"], !type.isEmpty { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func identityChips(_ props: [String: String]) -> some View {
        HStack(spacing: 6) {
            if let serial = props["ro.serialno"], !serial.isEmpty { chip("number", serial) }
            if let abi = props["ro.product.cpu.abi"], !abi.isEmpty { chip("cpu", abi) }
            if let density = props["ro.sf.lcd_density"], !density.isEmpty { chip("display", "\(density) dpi") }
            if let patch = props["ro.build.version.security_patch"], !patch.isEmpty {
                chip("checkmark.shield", patch)
            }
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.caption.monospacedDigit()).textSelection(.enabled)
        }
        .foregroundStyle(.textMuted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.bgRoot, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.borderSubtle))
        .lineLimit(1)
    }

    // MARK: - Live gauges

    @ViewBuilder
    private var statsGrid: some View {
        if let overview {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                memoryCard(overview)
                storageCard(overview)
                batteryCard(overview)
                appsCard(overview)
            }
        } else {
            HubSection("Overview") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading memory, storage, and battery…").foregroundStyle(.textMuted)
                }
            }
        }
    }

    private func memoryCard(_ overview: DeviceOverview) -> some View {
        DeviceStatCard(
            icon: "memorychip", tint: .brandAccent, title: "Memory",
            value: formatKb(overview.ramUsedKb) + " used",
            caption: "of \(formatKb(overview.ramTotalKb)) · \(formatKb(overview.ramAvailableKb)) free",
            fraction: fraction(overview.ramUsedKb, of: overview.ramTotalKb)
        )
    }

    private func storageCard(_ overview: DeviceOverview) -> some View {
        DeviceStatCard(
            icon: "internaldrive", tint: .blue, title: "Storage",
            value: formatKb(overview.storageUsedKb) + " used",
            caption: "of \(formatKb(overview.storageTotalKb)) · \(formatKb(overview.storageAvailableKb)) free",
            fraction: fraction(overview.storageUsedKb, of: overview.storageTotalKb)
        )
    }

    private func batteryCard(_ overview: DeviceOverview) -> some View {
        let level = overview.batteryLevel
        var caption: [String] = []
        if let health = overview.batteryHealth { caption.append("health \(health)") }
        if let cycles = overview.batteryCycleCount { caption.append("\(cycles) cycles") }
        return DeviceStatCard(
            icon: "battery.100", tint: batteryTint(level), title: "Battery",
            value: level.map { "\($0)%" } ?? "—",
            caption: caption.isEmpty ? "no battery details reported" : caption.joined(separator: " · "),
            fraction: level.map { Double($0) / 100 }
        )
    }

    private func appsCard(_ overview: DeviceOverview) -> some View {
        DeviceStatCard(
            icon: "square.grid.2x2", tint: .purple, title: "Apps",
            value: overview.userAppCount.map { "\($0) installed" } ?? "—",
            caption: overview.systemAppCount.map { "+ \($0) system apps" } ?? "system count unavailable",
            fraction: nil
        )
    }

    private func batteryTint(_ level: Int?) -> Color {
        guard let level else { return .textMuted }
        if level <= 20 { return .red }
        if level <= 45 { return .orange }
        return .green
    }

    private func fraction(_ part: Int?, of whole: Int?) -> Double? {
        guard let part, let whole, whole > 0 else { return nil }
        return Double(part) / Double(whole)
    }

    // MARK: - Raw property search

    private func filtered(_ props: [String: String]) -> some View {
        let matches = props
            .filter {
                $0.key.localizedCaseInsensitiveContains(search)
                    || $0.value.localizedCaseInsensitiveContains(search)
            }
            .sorted { $0.key < $1.key }

        return Group {
            if matches.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(matches, id: \.key) { prop in
                    HStack(alignment: .firstTextBaseline) {
                        Text(prop.key)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Text(prop.value)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.textMuted)
                            .textSelection(.enabled)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func formatKb(_ kb: Int?) -> String {
        guard let kb else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .memory)
    }

    private func load() async {
        props = nil
        overview = nil
        guard let serial = state.targetSerials.first else { return }
        let (fetchedProps, fetchedOverview) = await CommandLog.userInitiated(feature: "device-info") {
            async let propsResult = (try? DeviceProps.all(client: state.env.client, serial: serial)) ?? [:]
            async let overviewResult = DeviceOverview.fetch(client: state.env.client, serial: serial)
            return await (propsResult, overviewResult)
        }
        guard !Task.isCancelled else { return }
        props = fetchedProps
        overview = fetchedOverview
    }
}

/// One gauge card on the Device Info screen: icon + quiet title, a big value
/// line, a caption, and an optional usage meter.
private struct DeviceStatCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let caption: String
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.textMuted)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.textMuted)
                    .lineLimit(1)
            }
            if let fraction {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.borderSubtle))
    }
}
