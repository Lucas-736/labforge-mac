import SwiftUI

/// What kind of moment to celebrate.
enum CelebrationKind: Sendable, Equatable {
    /// Check-in: full warm ember burst + concentric ripple.
    case checkIn
    /// Check-out: gentler, smaller burst.
    case checkOut
}

/// A single celebration request. A new `id` replays the animation.
struct CelebrationTrigger: Sendable, Equatable, Identifiable {
    let id: UUID
    let kind: CelebrationKind

    init(kind: CelebrationKind) {
        self.id = UUID()
        self.kind = kind
    }
}

/// Warm ember / spark celebration drawn with `Canvas` + `TimelineView(.animation)`.
///
/// The `TimelineView` only exists while a burst is playing (~2.2s); when idle the view renders an
/// empty, hit-test-transparent placeholder, so no animation frames are consumed.
struct SparkCelebrationView: View {
    let trigger: CelebrationTrigger?

    static let duration: TimeInterval = 2.2

    @State private var playing: Playback?

    private struct Playback: Equatable {
        let id: UUID
        let kind: CelebrationKind
        let start: Date
        let seed: UInt64
    }

    var body: some View {
        ZStack {
            if let playing {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(playing.start)
                    Canvas(rendersAsynchronously: false) { gc, size in
                        Self.draw(in: &gc, size: size, t: t, kind: playing.kind, seed: playing.seed)
                    }
                }
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, newValue in
            guard let newValue else { return }
            start(newValue)
        }
        .task(id: playing?.id) {
            guard let id = playing?.id else { return }
            try? await Task.sleep(for: .seconds(Self.duration + 0.05))
            guard !Task.isCancelled, playing?.id == id else { return }
            playing = nil
        }
        .onDisappear { playing = nil }
    }

    private func start(_ trigger: CelebrationTrigger) {
        let playback = Playback(id: trigger.id, kind: trigger.kind, start: Date(),
                                seed: UInt64(truncatingIfNeeded: trigger.id.hashValue))
        playing = playback
    }

    // MARK: Drawing

    private struct Particle {
        var angle: Double
        var speed: Double
        var size: Double
        var colorIndex: Int
        var delay: Double
        var drift: Double
    }

    private static let colors: [Color] = [ClaudePalette.primary, ClaudePalette.accentAmber, ClaudePalette.creamGold,
                                          ClaudePalette.primaryActive]

    /// SplitMix64 — deterministic pseudo-random particles per burst.
    private struct SeededRNG {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }

    private static func particles(kind: CelebrationKind, seed: UInt64) -> [Particle] {
        var rng = SeededRNG(state: seed)
        let count = kind == .checkIn ? 46 : 22
        return (0..<count).map { i in
            Particle(
                angle: Double(i) / Double(count) * 2 * .pi + (rng.next() - 0.5) * 0.5,
                speed: (kind == .checkIn ? 120 : 70) + rng.next() * (kind == .checkIn ? 150 : 70),
                size: 1.6 + rng.next() * (kind == .checkIn ? 3.2 : 2.2),
                colorIndex: Int(rng.next() * Double(colors.count)) % colors.count,
                delay: rng.next() * 0.25,
                drift: (rng.next() - 0.5) * 30
            )
        }
    }

    private static func draw(in gc: inout GraphicsContext, size: CGSize, t: Double, kind: CelebrationKind, seed: UInt64) {
        guard t >= 0, t <= duration else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let progress = t / duration

        // Concentric ripples — soft coral hairlines expanding and fading.
        let rippleCount = kind == .checkIn ? 3 : 2
        let maxRadius = min(size.width, size.height) * (kind == .checkIn ? 0.55 : 0.38)
        for i in 0..<rippleCount {
            let local = progress * 1.35 - Double(i) * 0.18
            guard local > 0, local < 1 else { continue }
            let eased = 1 - pow(1 - local, 3)
            let r = maxRadius * eased
            let alpha = (1 - local) * 0.45
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            gc.stroke(Path(ellipseIn: rect), with: .color(ClaudePalette.primary.opacity(alpha)), lineWidth: 1.2)
        }

        // Embers — decelerating outward, falling gently, cooling from coral to cream gold.
        for p in particles(kind: kind, seed: seed) {
            let lt = t - p.delay
            guard lt > 0 else { continue }
            let life = duration - p.delay
            let lp = min(lt / life, 1)
            let travel = p.speed * (1 - pow(1 - lp, 2.4)) * 0.9
            let gravity = 26 * lt * lt
            let x = center.x + cos(p.angle) * travel + p.drift * lp
            let y = center.y + sin(p.angle) * travel + gravity
            let alpha = pow(1 - lp, 1.4)
            let s = p.size * (1 - lp * 0.55)
            let color = colors[p.colorIndex].opacity(alpha)
            // Short trailing streak toward the origin.
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x - cos(p.angle) * s * 2.6, y: y - sin(p.angle) * s * 2.6))
            gc.stroke(streak, with: .color(color.opacity(0.55)), lineWidth: max(0.6, s * 0.45))
            gc.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)), with: .color(color))
        }

        // Brief central flash — warm, low alpha, no glow.
        if progress < 0.22 {
            let a = (1 - progress / 0.22) * 0.22
            let r = 18 + 40 * progress
            gc.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                    with: .color(ClaudePalette.accentAmber.opacity(a)))
        }
    }
}
