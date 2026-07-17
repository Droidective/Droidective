import ADBKit
import SwiftUI

/// Which tab the wireless sheet opens on — doubles as the `.sheet(item:)`
/// payload for the device bar's "Pair new device…" / "Connect to device…"
/// menu entries.
enum WirelessSheetMode: String, CaseIterable, Identifiable {
    case pair, connect, usb

    var id: String { rawValue }

    var tabTitle: String {
        switch self {
        case .pair: "Pair new device"
        case .connect: "Already paired"
        case .usb: "Via USB cable"
        }
    }
}

/// A guided modal for getting a device onto wireless adb, opened from the
/// device dropdown. Three paths, one per tab: first-time Android 11+ pairing
/// (code + pairing port, then connect), plain connect for an already-paired
/// device, and the one-click USB→Wi-Fi bootstrap. Endpoints are single
/// paste-friendly "ip:port" fields (`ConnectionService.parseEndpoint`), exactly
/// as the phone displays them.
struct WirelessConnectSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var mode: WirelessSheetMode
    @State private var pairEndpoint = ""
    @State private var pairCode = ""
    @State private var pairConnectEndpoint = ""
    @State private var paired = false
    @State private var connectEndpoint = ""
    @State private var busy = false
    @State private var status: Status?

    private struct Status: Equatable {
        let ok: Bool
        let message: String
    }

    init(mode: WirelessSheetMode) {
        _mode = State(initialValue: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("", selection: $mode) {
                ForEach(WirelessSheetMode.allCases) { mode in
                    Text(mode.tabTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(busy)
            .onChange(of: mode) { status = nil }

            switch mode {
            case .pair: pairTab
            case .connect: connectTab
            case .usb: usbTab
            }

            Divider()

            HStack(spacing: 8) {
                statusLine
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 470)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.brandAccent)
                .frame(width: 36, height: 36)
                .background(Color.brandAccent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect over Wi-Fi")
                    .font(.app(.headline))
                Text("Debug without a cable. The device and this Mac must be on the same Wi-Fi network.")
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pair (Android 11+, first time)

    private var pairTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepRow(number: 1, title: "Open pairing on the device") {
                Text("Settings ▸ Developer options ▸ **Wireless debugging** ▸ **Pair device with pairing code**.")
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StepRow(number: 2, title: "Enter what the pairing dialog shows") {
                HStack(alignment: .bottom, spacing: 12) {
                    HubField("IP address & pairing port", prompt: "192.168.1.42:37123", text: $pairEndpoint)
                    HubField("Pairing code", prompt: "123456", text: $pairCode)
                        .frame(width: 110)
                    Button("Pair") { runPair() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || pairInput == nil)
                }
            }

            StepRow(number: 3, title: "Connect", done: paired) {
                Text("After pairing, Droidective looks up the connect port and connects by itself. If it can't, use the port on the main Wireless debugging screen — it differs from the pairing port.")
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .bottom, spacing: 12) {
                    HubField("IP address & port", prompt: "192.168.1.42:40913", text: $pairConnectEndpoint)
                    Button("Connect") { runConnect(pairConnectEndpoint) }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || ConnectionService.parseConnectEndpoint(pairConnectEndpoint) == nil)
                }
            }
        }
    }

    // MARK: - Connect (already paired)

    private var connectTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For a device that was paired before, or one already switched to Wi-Fi (port 5555). Find the address under Settings ▸ Developer options ▸ Wireless debugging.")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 12) {
                HubField("IP address & port", prompt: "192.168.1.42:5555", text: $connectEndpoint)
                Button("Connect") { runConnect(connectEndpoint) }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || ConnectionService.parseConnectEndpoint(connectEndpoint) == nil)
            }
        }
    }

    // MARK: - USB bootstrap

    private var usbDevices: [Device] {
        state.devices.filter { $0.platform == .android && !$0.isWireless && $0.isReady }
    }

    private var usbTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The easiest way — plug the device in once, click below, then unplug. Droidective switches it to Wi-Fi debugging and connects automatically.")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if usbDevices.isEmpty {
                Label("No USB device detected — plug one in and it appears here.", systemImage: "cable.connector")
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
            } else {
                ForEach(usbDevices) { device in
                    HStack {
                        Text(device.label)
                        Spacer()
                        Button("Switch to Wi-Fi") { runTcpip(device.serial) }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)
                    }
                }
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusLine: some View {
        if busy {
            ProgressView()
                .controlSize(.small)
            Text("Working…")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
        } else if let status {
            Image(systemName: status.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status.ok ? Color.brandAccent : .red)
            Text(status.message)
                .font(.app(.callout))
                .foregroundStyle(status.ok ? .textMain : Color.red)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    /// Step 2's inputs, valid only when the endpoint has a port and a code is
    /// typed — gates the Pair button.
    private var pairInput: (host: String, port: String, code: String)? {
        guard let endpoint = completeEndpoint(pairEndpoint) else { return nil }
        let code = pairCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return nil }
        return (endpoint.host, endpoint.port ?? "", code)
    }

    /// The pairing endpoint must parse *and* carry an explicit port — the
    /// pairing port is random per session, so nothing sensible to default to.
    private func completeEndpoint(_ text: String) -> WirelessEndpoint? {
        guard let endpoint = ConnectionService.parseEndpoint(text), endpoint.port != nil else { return nil }
        return endpoint
    }

    /// Pair, then finish the job when possible: a paired device advertises
    /// its connect port over mDNS (`_adb-tls-connect._tcp`), so on success we
    /// look it up and connect without asking for the port. When discovery
    /// comes up empty (older adb, mDNS off, different subnet), fall back to
    /// prefilling "ip:" so the user only types the port from the Wireless
    /// debugging screen.
    private func runPair() {
        guard let input = pairInput else { return }
        let connection = state.env.engine.connection
        busy = true
        status = nil
        Task {
            await CommandLog.userInitiated {
                do {
                    let result = try await connection.pair(
                        host: input.host, port: input.port, code: input.code)
                    status = Status(ok: result.ok, message: result.message)
                    guard result.ok else { return }
                    paired = true
                    if pairConnectEndpoint.isEmpty {
                        pairConnectEndpoint = "\(input.host):"
                    }
                    status = Status(ok: true, message: "Paired — looking up the connect port…")
                    guard let endpoint = await connection.discoverConnectEndpoint(host: input.host),
                          let port = endpoint.port else {
                        status = Status(
                            ok: true,
                            message: "Paired — enter the port from the Wireless debugging screen to connect.")
                        return
                    }
                    pairConnectEndpoint = "\(endpoint.host):\(port)"
                    let connected = try await connection.connect(host: endpoint.host, port: port)
                    status = Status(ok: connected.ok, message: connected.message)
                    if connected.ok {
                        finishConnected(connected, address: "\(endpoint.host):\(port)")
                    }
                } catch {
                    status = Status(ok: false, message: error.localizedDescription)
                }
            }
            busy = false
        }
    }

    /// Connect fields take a bare IP too — it defaults to adb's port 5555.
    private func runConnect(_ endpointText: String) {
        guard let endpoint = ConnectionService.parseConnectEndpoint(endpointText),
              let port = endpoint.port else { return }
        let connection = state.env.engine.connection
        run({ try await connection.connect(host: endpoint.host, port: port) }) { result in
            finishConnected(result, address: "\(endpoint.host):\(port)")
        }
    }

    private func runTcpip(_ serial: String) {
        let connection = state.env.engine.connection
        run({ try await connection.enableTcpip(serial: serial) }) { result in
            // tcpip can succeed without the auto-connect (no readable IP) —
            // only a real "Connected" closes the sheet.
            if let address = result.copyText, result.message.hasPrefix("Connected") {
                finishConnected(result, address: address)
            }
        }
    }

    /// A device is now reachable over Wi-Fi: select it, hand the confirmation
    /// to a toast (it must outlive the sheet), and close.
    private func finishConnected(_ result: FeatureResult, address: String) {
        state.requestDevice(address)
        state.showToast(Toast(message: result.message, ok: true, copyText: result.copyText, important: true))
        dismiss()
    }

    private func run(
        _ operation: @escaping @Sendable () async throws -> FeatureResult,
        onSuccess: @escaping (FeatureResult) -> Void
    ) {
        busy = true
        status = nil
        Task {
            await CommandLog.userInitiated {
                do {
                    let result = try await operation()
                    status = Status(ok: result.ok, message: result.message)
                    if result.ok { onSuccess(result) }
                } catch {
                    status = Status(ok: false, message: error.localizedDescription)
                }
            }
            busy = false
        }
    }
}

/// A numbered step: an accent-tinted circled number (a checkmark once `done`)
/// beside a bold step title and its controls.
private struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    var done = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                } else {
                    Text("\(number)")
                        .font(.app(.footnote).bold())
                }
            }
            .foregroundStyle(Color.brandAccent)
            .frame(width: 22, height: 22)
            .background(Color.brandAccent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.app(.subheadline))
                    .fontWeight(.semibold)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
