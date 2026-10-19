import ADBKit
import SwiftUI

/// The phone the device menu's "Set Up Droidective on This Phone…" opens the
/// sheet for — the `.sheet(item:)` payload.
struct PhoneSetupTarget: Identifiable {
    let serial: String
    let name: String

    var id: String { serial }
}

/// One-click set-up of Droidective for Android on a connected phone, opened
/// from the device dropdown: three rows for what is done, and one button that
/// grants the two permissions only adb can and starts Shizuku if it is
/// stopped. The logic is `PhoneAppSetupService`; this only shows its answers.
struct PhoneSetupSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let target: PhoneSetupTarget
    /// Every status the sheet reads, so the device bar can stop offering
    /// set-up the moment it is done.
    let onStatus: (PhoneAppSetupStatus) -> Void

    @State private var status: PhoneAppSetupStatus?
    /// True until the first read answers, either way.
    @State private var checking = true
    @State private var busy = false
    @State private var result: Result?

    private struct Result: Equatable {
        let ok: Bool
        let message: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(alignment: .leading, spacing: 12) {
                SetupRow(title: "App installed", state: appRow)
                SetupRow(title: "Permissions granted", state: permissionsRow)
                SetupRow(title: "Shizuku running", state: shizukuRow)
            }

            Divider()

            HStack(spacing: 8) {
                resultLine
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Set Up") { runSetUp() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || status?.needsSetup != true)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await load() }
    }

    private static let subtitle =
        "Grants the app two permissions only adb can, and starts Shizuku if it's there."

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.brandAccent)
                .frame(width: 36, height: 36)
                .background(Color.brandAccent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Set Up Droidective on \(target.name)")
                    .font(.app(.headline))
                Text(Self.subtitle)
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Rows

    /// A row before the phone has answered — or after it could not.
    private var unread: SetupRow.State {
        checking ? .checking : .unavailable("Couldn't read the phone.")
    }

    private var appRow: SetupRow.State {
        guard let status else { return unread }
        guard status.appInstalled else {
            return .todo("Install Droidective for Android on the phone first.")
        }
        let name = "Droidective for Android"
        return .done(status.appVersion.map { "\(name) \($0)" } ?? name)
    }

    private var permissionsRow: SetupRow.State {
        guard let status else { return unread }
        guard status.appInstalled else { return .unavailable("Needs the app.") }
        let names = PhoneAppSetupService.requiredPermissions.map(PhoneAppSetupService.shortName)
        guard status.permissionsGranted else {
            let missing = status.missingPermissions.map(PhoneAppSetupService.shortName)
            return .todo("Missing \(missing.joined(separator: " and ")).")
        }
        return .done(names.joined(separator: " and "))
    }

    private var shizukuRow: SetupRow.State {
        guard let status else { return unread }
        guard status.shizukuInstalled else {
            return .unavailable("Not installed. Optional — it gives the app shell access.")
        }
        return status.shizukuRunning ? .done("Running") : .todo("Installed, not running.")
    }

    // MARK: - Result

    @ViewBuilder
    private var resultLine: some View {
        if busy || checking {
            ProgressView()
                .controlSize(.small)
            Text(busy ? "Setting up…" : "Checking the phone…")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
        } else if let result {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.ok ? Color.brandAccent : .red)
            Text(result.message)
                .font(.app(.callout))
                .foregroundStyle(result.ok ? .textMain : Color.red)
                .lineLimit(3)
                .textSelection(.enabled)
        } else if status?.needsSetup == false, status?.appInstalled == true {
            Text("Nothing to do — this phone is set up.")
                .font(.app(.callout))
                .foregroundStyle(.textMuted)
        }
    }

    // MARK: - Actions

    private func load() async {
        let service = state.env.engine.phoneAppSetup
        let serial = target.serial
        await CommandLog.userInitiated {
            do {
                apply(try await service.status(serial: serial))
            } catch {
                guard !Task.isCancelled else { return }
                result = Result(ok: false, message: error.localizedDescription)
            }
        }
        checking = false
    }

    private func runSetUp() {
        let service = state.env.engine.phoneAppSetup
        let serial = target.serial
        busy = true
        result = nil
        Task {
            await CommandLog.userInitiated {
                do {
                    let outcome = try await service.setUp(serial: serial)
                    apply(outcome.status)
                    result = Result(
                        ok: outcome.failure == nil, message: outcome.failure ?? "All set.")
                } catch {
                    result = Result(ok: false, message: error.localizedDescription)
                }
            }
            busy = false
        }
    }

    private func apply(_ read: PhoneAppSetupStatus) {
        guard !Task.isCancelled else { return }
        status = read
        onStatus(read)
    }
}

/// One line of the checklist: a state glyph, the step's name, and what the
/// phone reported for it.
private struct SetupRow: View {
    enum State {
        case checking
        case done(String)
        case todo(String)
        /// Nothing set-up can do here — a missing prerequisite, or an optional
        /// piece that is absent.
        case unavailable(String)
    }

    let title: String
    let state: State

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            glyph
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.subheadline))
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.app(.callout))
                    .foregroundStyle(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandAccent)
        case .todo:
            Image(systemName: "circle")
                .foregroundStyle(.textMuted)
        case .unavailable:
            Image(systemName: "minus.circle")
                .foregroundStyle(.textMuted)
        }
    }

    private var detail: String {
        switch state {
        case .checking: "Checking…"
        case .done(let text), .todo(let text), .unavailable(let text): text
        }
    }
}
