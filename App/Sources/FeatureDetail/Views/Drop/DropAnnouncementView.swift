import ADBKit
import SwiftUI

/// What the surface says while a drag is over it: the verb, what it applies
/// to, and — when the drop also has a second option — the line that names it.
///
/// Never interactive. The drop region is the view underneath; this only draws,
/// so it can't take a click away from a mirror the user is tapping.
struct DropAnnouncementView: View {
    let announcement: DropAnnouncement
    /// Insets the dashed frame. The mirror leaves a margin so the video still
    /// reads underneath; the window-level fallback fills its area.
    var inset: CGFloat = 14

    private var tint: Color { announcement.refusal ? .orange : .brandAccent }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .padding(inset)
            VStack(spacing: 8) {
                Image(systemName: announcement.symbol)
                    .font(.app(size: 34))
                    .foregroundStyle(tint)
                Text(announcement.verb)
                    .font(.app(.title3).weight(.semibold))
                    .foregroundStyle(.white)
                Text(announcement.detail)
                    .font(.app(.caption))
                    .foregroundStyle(.white.opacity(0.75))
                if let alternative = announcement.alternative {
                    Text(alternative)
                        .font(.app(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 6)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
