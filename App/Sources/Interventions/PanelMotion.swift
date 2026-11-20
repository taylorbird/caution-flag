import AppKit
import SwiftUI

/// Drives the hot panel's small animations (waving flag, rolling tape, stopwatch hand,
/// tile nudge). A plain Timer, because TimelineView and repeat-forever animations
/// don't reliably tick in a non-activating panel of an app that's never active.
/// It runs only while the panel is up, so a hidden panel costs nothing.
@MainActor
final class MotionClock: ObservableObject {
    /// Seconds since the clock started; stays 0 when motion is off.
    @Published private(set) var t: Double = 0
    private var timer: Timer?
    private var started = Date()

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        started = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.t = Date().timeIntervalSince(self.started)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        t = 0
    }

    /// Whether to animate: the system Reduce Motion setting, unless the user overrode it.
    static func shouldAnimate(override: Bool) -> Bool {
        override || !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// The header flag: a pole and a cloth whose edges ripple.
struct WavingFlag: View {
    @ObservedObject var clock: MotionClock
    var color: Color
    var size: CGFloat = 24

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 24
            let t = clock.t
            context.fill(Path(roundedRect: CGRect(x: 4 * s, y: 2.5 * s, width: 2.5 * s, height: 19.5 * s),
                              cornerRadius: 1.25 * s), with: .color(color))
            // Cloth from x 6.25 to 19, y 4 to 14; the ripple grows toward the free end.
            let x0 = 6.25, x1 = 19.0, top = 4.0, bottom = 14.0
            func wave(_ x: Double) -> Double {
                let along = (x - x0) / (x1 - x0)
                return 1.1 * along * sin(along * 1.8 * .pi - t * 2 * .pi / 1.6)
            }
            var cloth = Path()
            let steps = 16
            for i in 0...steps {
                let x = x0 + (x1 - x0) * Double(i) / Double(steps)
                let p = CGPoint(x: x * s, y: (top + wave(x)) * s)
                if i == 0 { cloth.move(to: p) } else { cloth.addLine(to: p) }
            }
            for i in stride(from: steps, through: 0, by: -1) {
                let x = x0 + (x1 - x0) * Double(i) / Double(steps)
                cloth.addLine(to: CGPoint(x: x * s, y: (bottom + wave(x)) * s))
            }
            cloth.closeSubpath()
            context.fill(cloth, with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Take 5" icon: a stopwatch whose hand sweeps once every five seconds.
struct StopwatchIcon: View {
    @ObservedObject var clock: MotionClock
    var color: Color
    var size: CGFloat = 26

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 24
            let style = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round)
            let center = CGPoint(x: 12 * s, y: 13 * s)
            context.stroke(Path(ellipseIn: CGRect(x: 4 * s, y: 5 * s, width: 16 * s, height: 16 * s)),
                           with: .color(color), style: style)
            var crown = Path()
            crown.move(to: CGPoint(x: 10 * s, y: 2 * s)); crown.addLine(to: CGPoint(x: 14 * s, y: 2 * s))
            crown.move(to: CGPoint(x: 12 * s, y: 2 * s)); crown.addLine(to: CGPoint(x: 12 * s, y: 5 * s))
            context.stroke(crown, with: .color(color), style: style)
            let angle = clock.t / 5 * 2 * .pi
            var hand = Path()
            hand.move(to: center)
            hand.addLine(to: CGPoint(x: center.x + 4.5 * s * sin(angle), y: center.y - 4.5 * s * cos(angle)))
            context.stroke(hand, with: .color(color), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
