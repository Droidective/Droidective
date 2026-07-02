import ADBKit
import AppKit
import SwiftUI

/// One expandable command-log entry: the command, its exit code/duration, and
/// (when expanded) its stdout/stderr. Used by the Settings ▸ Command Log sheet.
struct CommandLogRow: View {
    let entry: CommandLogEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.textMuted)
                    Text(entry.command)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(expanded ? nil : 1)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text(Self.exitLabel(entry))
                        .font(.caption)
                        .foregroundStyle(entry.exitCode == 0 ? Color.brandAccent : Color.red)
                    Text(entry.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if !entry.stdout.isEmpty {
                    outputBlock(entry.stdout, tint: nil)
                }
                if !entry.stderr.isEmpty {
                    outputBlock(entry.stderr, tint: .red)
                }
                if entry.stdout.isEmpty && entry.stderr.isEmpty {
                    Text("(no output)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 18)
                }
            }
        }
    }

    @ViewBuilder
    private func outputBlock(_ text: String, tint: Color?) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(tint ?? .primary)
            .textSelection(.enabled)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((tint ?? .textMuted).opacity(tint == nil ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    static func exitLabel(_ entry: CommandLogEntry) -> String {
        let code = entry.exitCode.map(String.init) ?? "killed"
        let ms = Int(entry.duration.components.seconds * 1000)
            + Int(entry.duration.components.attoseconds / 1_000_000_000_000_000)
        return "exit \(code) · \(ms)ms"
    }
}
