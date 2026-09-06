import ADBKit
import AppKit
import SwiftUI

/// The Video Editor feature: open (or drop) any video and edit it. Fresh
/// recordings open the same editor automatically from Screen Record, and a
/// video opened from Finder arrives through `AppState.pendingVideo`.
struct VideoEditorView: View {
    @Environment(AppState.self) private var state
    @State private var openedURL: URL?

    var body: some View {
        Group {
            if let url = openedURL {
                VideoEditorPane(source: .file(url)) { openedURL = nil }
                    .id(url)
            } else {
                emptyState
            }
        }
        // A Finder open (or a second one while the editor is already up)
        // routes the feature here and leaves the URL waiting. Claimed rather
        // than read, so returning to the tab later doesn't reopen it.
        .task(id: state.pendingVideo) {
            if let url = state.claimPendingVideo() { openedURL = url }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "film").font(.app(size: 46)).foregroundStyle(.textMuted)
                Text("Edit a video").font(.app(.title3).weight(.semibold))
                Text("Open a video to trim, rotate, crop, change speed, convert, and compress —\nor record one from Screen Record.")
                    .multilineTextAlignment(.center).foregroundStyle(.textMuted)
            }
            Button { openFile() } label: {
                Label("Open video…", systemImage: "folder").frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        // Filtered, where this used to take whatever was dropped and hand an
        // .apk or a .txt to AVFoundation as if it were a video. What isn't a
        // video now goes to the feature that can use it instead of a toast
        // saying no.
        .featureFileDrop(
            claims: { PlayableVideo.filter($0).first.map { [$0] } ?? [] },
            perform: { openedURL = $0.first })
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PlayableVideo.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { openedURL = url }
    }
}
