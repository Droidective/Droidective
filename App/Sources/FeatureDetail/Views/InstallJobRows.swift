import SwiftUI

/// Live install status for the given packages — a spinner per device while the
/// install runs, then a check or the failure reason. Shared by the Install App
/// screen, the opened-package screen, and the AAB converter; reads
/// `AppState.installJobs`, showing the latest job per package × device so a
/// retry replaces its old row instead of stacking a history. A split bundle
/// also reports what it's doing (unpacking, copying expansion files).
struct InstallJobRows: View {
    @Environment(AppState.self) private var state
    let urls: [URL]
    /// Prefix rows with the package name (for screens installing several files).
    var showsApkName = false

    private var jobs: [InstallJob] {
        var seen = Set<String>()
        return state.installJobs.reversed()
            .filter { urls.contains($0.packageURL) && seen.insert("\($0.packageURL.path)|\($0.serial)").inserted }
            .reversed()
    }

    var body: some View {
        let jobs = jobs
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(jobs) { row($0) }
            }
        }
    }

    private func row(_ job: InstallJob) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            statusIcon(job.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(showsApkName ? "\(job.packageName) → \(job.deviceLabel)" : job.deviceLabel)
                    .font(.app(.callout))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .failed(let reason) = job.status {
                    Text(reason)
                        .font(.app(.caption))
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                } else if let stage = job.stage {
                    Text(stage)
                        .font(.app(.caption))
                        .foregroundStyle(.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func statusIcon(_ status: InstallJob.Status) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
