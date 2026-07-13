import SwiftUI

/// Raycast-style confetti: bursts of colored pieces launched from the
/// window's bottom corners and center, tumbling up and falling under gravity
/// while they fade. Fires once per `trigger` bump and cleans itself up, so
/// the animation timeline never runs while idle. Never intercepts clicks.
struct ConfettiCelebration: View {
    let trigger: Int
    @State private var activeBurst: Int?

    var body: some View {
        ZStack {
            if let burst = activeBurst {
                ConfettiBurst()
                    .id(burst)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, fired in
            guard fired > 0 else { return }
            activeBurst = fired
            Task {
                try? await Task.sleep(for: .seconds(ConfettiBurst.duration + 0.5))
                if activeBurst == fired { activeBurst = nil }
            }
        }
    }
}

/// One full confetti volley, drawn in a Canvas from a pure ballistic model —
/// each piece is fixed at spawn (position, velocity, spin, color) and its
/// state at any instant derives from elapsed time alone, so the Canvas just
/// evaluates, never mutates.
private struct ConfettiBurst: View {
    /// Seconds until the last-launched piece has fully faded.
    static let duration: Double = 3.6

    private static let colors: [Color] = [
        .brandAccent, .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink,
    ]

    private struct Piece {
        let startX: CGFloat
        let velocity: CGVector  // unit-space / second; negative dy = upward
        let colorIndex: Int
        let size: CGFloat
        let spin: Double        // radians / second
        let phase: Double
        let delay: Double
        let isRect: Bool
    }

    /// Three cannons — bottom corners angled inward, center straight up.
    private static func makePieces() -> [Piece] {
        let emitters: [(x: CGFloat, dx: ClosedRange<CGFloat>, count: Int)] = [
            (0.02, 0.10 ... 0.60, 50),
            (0.98, -0.60 ... -0.10, 50),
            (0.50, -0.25 ... 0.25, 40),
        ]
        var pieces: [Piece] = []
        for emitter in emitters {
            for _ in 0 ..< emitter.count {
                pieces.append(Piece(
                    startX: emitter.x + CGFloat.random(in: -0.02 ... 0.02),
                    velocity: CGVector(
                        dx: CGFloat.random(in: emitter.dx),
                        dy: -CGFloat.random(in: 0.9 ... 1.8)
                    ),
                    colorIndex: Int.random(in: 0 ..< Self.colors.count),
                    size: CGFloat.random(in: 5 ... 11),
                    spin: Double.random(in: -8 ... 8),
                    phase: Double.random(in: 0 ... (2 * .pi)),
                    delay: Double.random(in: 0 ... 0.3),
                    isRect: Bool.random()
                ))
            }
        }
        return pieces
    }

    private let pieces = ConfettiBurst.makePieces()
    private let launchedAt = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(launchedAt)
                for piece in pieces {
                    draw(piece, at: elapsed - piece.delay, in: context, size: size)
                }
            }
        }
    }

    private func draw(_ piece: Piece, at life: Double, in context: GraphicsContext, size: CGSize) {
        let fadeStart = 2.4
        guard life > 0, life < ConfettiBurst.duration else { return }
        // Ballistics in unit space: constant sideways drift plus a light sway,
        // gravity pulling the rise back down.
        let gravity: CGFloat = 1.1
        let x = piece.startX + piece.velocity.dx * life + sin(piece.phase + life * 3) * 0.012
        let y = 1.04 + piece.velocity.dy * life + 0.5 * gravity * life * life
        guard y < 1.1 else { return }
        var ctx = context
        ctx.translateBy(x: x * size.width, y: y * size.height)
        ctx.rotate(by: .radians(piece.spin * life + piece.phase))
        // A cosine squeeze on the height reads as the piece tumbling in 3D.
        ctx.scaleBy(x: 1, y: max(0.25, abs(cos(piece.phase + life * 5))))
        ctx.opacity = life > fadeStart ? max(0, 1 - (life - fadeStart) / (ConfettiBurst.duration - fadeStart)) : 1
        let bounds = CGRect(
            x: -piece.size / 2, y: -piece.size * 0.3,
            width: piece.size, height: piece.size * 0.6
        )
        let path = piece.isRect
            ? Path(roundedRect: bounds, cornerRadius: 1)
            : Path(ellipseIn: CGRect(x: -piece.size / 2, y: -piece.size / 2, width: piece.size, height: piece.size))
        ctx.fill(path, with: .color(Self.colors[piece.colorIndex]))
    }
}
