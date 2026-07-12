import ADBKit
import SwiftUI

/// Connection hub — the device's current Wi-Fi network and IP, port reversing,
/// the wireless ADB pairing flow, and Private DNS on one scrollable screen.
/// Copy IP also stays a one-click sidebar action; the other gathered features
/// stay searchable and hotkey-able. Wi-Fi, Network Speed, and Emulators remain
/// their own screens.
struct NetworkConnectionView: View {
    @Environment(AppState.self) private var state
    @State private var reversePort = "8081"
    @State private var wifiStatus: WifiStatus?
    @State private var statusLoaded = false

    /// The hub's status sections are adb-backed; a selected iOS Simulator
    /// gets an inline notice instead of adb runs against its UDID. The
    /// wireless-connect flow stays available — it needs no ready device.
    private var selectedSimulator: Device? {
        guard let serial = state.targetSerials.first else { return nil }
        return state.devices.first { $0.serial == serial && $0.platform == .iosSimulator }
    }

    var body: some View {
        HubColumn {
            if let simulator = selectedSimulator {
                HubSection("This device") {
                    Text("\(simulator.label) is an iOS Simulator — Wi-Fi status, port reversing, and Private DNS are Android features. Wireless ADB below still works for Android devices on your network.")
                        .foregroundStyle(.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                deviceSection

                HubSection(
                    "Reverse a port",
                    subtitle: "adb reverse tunnels a device port to this Mac — e.g. Metro on 8081."
                ) {
                    HStack(spacing: 10) {
                        TextField("", text: $reversePort, prompt: Text("8081"))
                            .brandField()
                            .labelsHidden()
                            .frame(maxWidth: 120)
                        Button("Forward") {
                            run("reverse-port", ["port": .string(reversePort.trimmingCharacters(in: .whitespaces))])
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.targetSerials.isEmpty || reversePort.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            WirelessAdbSection()
            if selectedSimulator == nil {
                PrivateDnsSection()
            }
        }
    }

    /// The device's live network context. Pairing and wireless connect below
    /// need this IP, so it's shown up front instead of behind a blind copy.
    private var deviceSection: some View {
        HubSection(
            "This device",
            subtitle: "The Wi-Fi network and IP address — pairing below connects to this IP.",
            accessory: {
                Button {
                    Task { await loadStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(IconButtonStyle())
                .help("Refresh")
                .disabled(state.targetSerials.isEmpty)
            }
        ) {
            if state.targetSerials.isEmpty {
                Text("Connect a device to see its network.")
                    .foregroundStyle(.textMuted)
            } else if !statusLoaded {
                ProgressView().controlSize(.small)
            } else if let ip = wifiStatus?.ipAddress {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let ssid = wifiStatus?.ssid {
                            Text(ssid).font(.app(.caption)).foregroundStyle(.textMuted)
                        }
                        Text(ip)
                            .font(.app(.title3).weight(.semibold))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        run("get-ip")
                    } label: {
                        Label("Copy IP", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("No Wi-Fi connection — wireless debugging and pairing need the device on Wi-Fi.")
                    .foregroundStyle(.textMuted)
            }
        }
        .task(id: state.targetSerials.first ?? "") { await loadStatus() }
    }

    private func loadStatus() async {
        statusLoaded = false
        guard let serial = state.targetSerials.first else { return }
        let status = await CommandLog.userInitiated {
            await state.env.engine.wifi.status(serial: serial)
        }
        guard !Task.isCancelled else { return }
        wifiStatus = status
        statusLoaded = true
    }

    private func run(_ id: String, _ params: [String: FeatureValue] = [:]) {
        guard let feature = FeatureRegistry.byID[id] else { return }
        Task { await state.run(feature: feature, params: params) }
    }
}
