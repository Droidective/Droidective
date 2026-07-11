import ADBKit
import SwiftUI

/// Searchable installed-app picker shared by the restart flows (Reactotron,
/// JS Console), shown when the running app can't be detected automatically —
/// or when restarting the detected one failed. Lists the device's third-party
/// packages; picking one calls `onPick` and closes.
struct RestartAppPickerSheet: View {
    let serial: String?
    let onPick: (String) -> Void

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [String] = []
    @State private var loading = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.localizedCaseInsensitiveContains(search)
                || restartAppDisplayName($0).localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.brandAccent.opacity(0.16)).frame(width: 30, height: 30)
                    Image(systemName: "arrow.clockwise")
                        .font(.app(size: 13, weight: .semibold))
                        .foregroundStyle(.brandAccent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Restart app")
                        .font(.app(size: 13, weight: .semibold))
                    Text("Couldn't detect the running app — pick it to force-stop and relaunch")
                        .font(.app(size: 10))
                        .foregroundStyle(.textMuted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.app(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.app(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search apps…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.app(size: 12))
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.bgRoot, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.borderSubtle))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()
            content
        }
        .frame(width: 360, height: 440)
        .background(Color.bgSurface)
        .task { searchFocused = true; await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            hint("Loading apps…")
        } else if apps.isEmpty {
            hint("No third-party apps found")
        } else if filtered.isEmpty {
            hint("No matches")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.self) { package in
                        RestartAppPickerRow(package: package, serial: serial ?? "") {
                            dismiss()
                            onPick(package)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.app(.caption))
            .foregroundStyle(.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard let serial else { apps = []; return }
        loading = true
        defer { loading = false }
        let service = AppControlService(client: state.env.client)
        apps = await CommandLog.userInitiated {
            (try? await service.listInstalledPackages(serial: serial)) ?? []
        }
    }
}

private struct RestartAppPickerRow: View {
    let package: String
    let serial: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconView(packageId: package, name: restartAppDisplayName(package), serial: serial)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(restartAppDisplayName(package))
                        .font(.app(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(package)
                        .font(.app(size: 10, design: .monospaced))
                        .foregroundStyle(.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.brandAccent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Friendly app name from a package id ("com.foo.bar" → "Bar"), mirroring the
/// Apps feature's `AppListing.displayName`.
func restartAppDisplayName(_ packageId: String) -> String {
    packageId.split(separator: ".").last
        .map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? packageId
}
