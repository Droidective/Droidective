import SwiftUI

/// Live install status for the given APKs — a spinner per device while
/// `adb install` runs, then a check or the failure reason. Shared by the
/// Install App screen, the opened-APK screen, and the AAB converter; reads
/// `AppState.installJobs`, showing the latest job per APK × device so a retry
/// replaces its old row instead of stacking a history.
struct InstallJobRows: View {
    @Environment(AppState.self) private var state
    let urls: [URL]
    /// Prefix rows with the APK name (for screens installing several files).
    var showsApkName = false

    private var jobs: [InstallJob] {
        var seen = Set<String>()
        return state.installJobs.reversed()
            .filter { urls.contains($0.apkURL) && seen.insert("\($0.apkURL.path)|\($0.serial)").inserted }
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
                Text(showsApkName ? "\(job.apkName) → \(job.deviceLabel)" : job.deviceLabel)
                    .font(.app(.callout))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .failed(let reason) = job.status {
                    Text(reason)
                        .font(.app(.caption))
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
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
