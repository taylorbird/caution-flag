import CooldownCore
import SwiftUI

enum Palette {
    static let calm = Color(red: 0.30, green: 0.69, blue: 0.47)
    static let warm = Color(red: 0.95, green: 0.70, blue: 0.20)
    static let hot = Color(red: 0.89, green: 0.33, blue: 0.30)
    static let breath = Color(red: 0.36, green: 0.62, blue: 0.75)
    /// Brand colors, matching the app icon (assets/icon/caution-flag.svg).
    static let caution = Color(red: 0xF5 / 255, green: 0xC5 / 255, blue: 0x42 / 255)
    static let asphalt = Color(red: 0x1F / 255, green: 0x2A / 255, blue: 0x36 / 255)
}

/// The small, unobtrusive "this is reading a little hot" nudge.
struct PillView: View {
    let message: String
    let canExpand: Bool
    let onExpand: () -> Void
    /// Nil hides the "Not heated" button (e.g. on the thank-you state).
    let onNotHeated: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.warm).frame(width: 8, height: 8)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize()
            if canExpand {
                Button("Why?", action: onExpand)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.warm)
            }
            if let onNotHeated {
                Button("Not heated", action: onNotHeated)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("This one's fine. Saves it on this Mac so the tuning can improve.")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Not this time")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.warm.opacity(0.45), lineWidth: 1))
        .padding(8)
    }
}

/// The larger panel for drafts running hot. Deliberately loud, in the brand's
/// caution-tape look (see WelcomeHero): it should be impossible to miss.
/// Layout is design "B" (icon tiles) from the Caution Flag Hot Panel canvas.
struct HotPanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var clock: MotionClock
    let onCopy: (String) -> Void
    let onTakeFive: () -> Void
    let onSave: () -> Void
    let onClear: () -> Void
    let onNotHeated: () -> Void
    let onDismiss: () -> Void

    static let ink = Color(red: 0.95, green: 0.93, blue: 0.88)
    private static let corner: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            header
            HazardTape(phase: clock.t / 1.2).frame(height: 12)
            content
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
        }
        .frame(width: 400)
        .background(Palette.asphalt)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner))
        .overlay(RoundedRectangle(cornerRadius: Self.corner).strokeBorder(Palette.caution.opacity(0.9), lineWidth: 2))
        .padding(10)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            WavingFlag(clock: clock, color: Palette.asphalt)
            Text(model.headline)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.asphalt)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Palette.asphalt)
                    .frame(width: 28, height: 28)
                    .background(Palette.asphalt.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("I'm fine, dismiss")
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(
            ZStack {
                Palette.caution
                SpeedStripes(color: Palette.asphalt.opacity(0.06))
            }
        )
    }

    // MARK: - Body

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let assessment = model.assessment {
                Text(assessment.reason)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Self.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                if assessment.rewrite == nil && model.rewriteLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Palette.caution)
                        Text("Drafting a calmer version…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Self.ink.opacity(0.6))
                    }
                }
                if let rewrite = assessment.rewrite {
                    card(label: "A calmer version", accessory: {
                        Button { onCopy(rewrite) } label: {
                            Label(model.copied ? "Copied" : "Copy",
                                  systemImage: model.copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.caution)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Palette.caution.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }) {
                        Text(rewrite)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Self.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !model.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                card(label: "A note from you", accessory: { EmptyView() }) {
                    Text(model.notes)
                        .font(.system(size: 13.5).italic())
                        .foregroundStyle(Self.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.notedMisread {
            Text("Noted. Saved on this Mac for tuning, and nothing else changes.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Self.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            switch model.saveState {
            case .idle:
                HStack(spacing: 10) {
                    ActionTile(kind: .primary, title: "Take 5", clock: clock, action: onTakeFive) { color in
                        StopwatchIcon(clock: clock, color: color)
                    }
                    ActionTile(kind: .outline, title: "Save for later", clock: clock, action: onSave) { color in
                        Image(systemName: "bookmark")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(color)
                            .frame(width: 26, height: 26)
                    }
                    ActionTile(kind: .quiet, title: "I'm fine", clock: clock, action: onDismiss) { color in
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(color)
                            .frame(width: 26, height: 26)
                    }
                }
                Button("Not heated? Tell Caution Flag", action: onNotHeated)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Self.ink.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .help("Saves this draft on this Mac as a misread, for tuning later.")
            case .saved:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Saved privately on this Mac. Clear it from the message box too?")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Self.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Clear it", action: onClear)
                            .buttonStyle(TapeButtonStyle(kind: .primary))
                        Button("Keep it there", action: onDismiss)
                            .buttonStyle(TapeButtonStyle(kind: .outline))
                    }
                }
            case .cleared:
                Text("Cleared. It's waiting in Saved Drafts whenever you're ready.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Self.ink.opacity(0.7))
            }
        }
    }

    private func card<Accessory: View, Content: View>(
        label: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Palette.caution)
                Spacer(minLength: 8)
                accessory()
            }
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A big square-ish action: icon over label. Its icon bobs while hovered (when motion is on).
struct ActionTile<Icon: View>: View {
    enum Kind { case primary, outline, quiet }
    let kind: Kind
    let title: String
    @ObservedObject var clock: MotionClock
    let action: () -> Void
    @ViewBuilder let icon: (Color) -> Icon
    @State private var hovering = false

    private var foreground: Color {
        switch kind {
        case .primary: Palette.asphalt
        case .outline: Palette.caution
        case .quiet: HotPanelView.ink.opacity(0.85)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon(foreground)
                    .offset(y: hovering && clock.isRunning ? -3 * abs(sin(clock.t * .pi / 0.5)) : 0)
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(TilePressStyle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        switch kind {
        case .primary:
            shape.fill(Palette.caution)
                .background(shape.fill(Color(red: 0.72, green: 0.56, blue: 0.16)).offset(y: 3))
        case .outline:
            shape.strokeBorder(Palette.caution.opacity(0.75), lineWidth: 2)
        case .quiet:
            shape.fill(Color.white.opacity(0.07))
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 2))
        }
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Black-and-yellow hazard stripes, like a strip of caution tape. `phase` (in stripe
/// periods) scrolls them sideways.
struct HazardTape: View {
    var phase: Double = 0

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.caution))
            let band: CGFloat = 10
            let period = band * 2
            let shift = CGFloat(phase.truncatingRemainder(dividingBy: 1)) * period
            var x = -size.height - period + shift
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + band, y: size.height))
                path.addLine(to: CGPoint(x: x + band + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(Palette.asphalt))
                x += period
            }
        }
        .accessibilityHidden(true)
    }
}

/// The welcome banner's wide, faint diagonal bands.
struct SpeedStripes: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            let band: CGFloat = 26, gap: CGFloat = 46, slant = max(size.height, 60) * 0.6
            var x = -slant
            while x < size.width + slant {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + band, y: size.height))
                path.addLine(to: CGPoint(x: x + band + slant, y: 0))
                path.addLine(to: CGPoint(x: x + slant, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(color))
                x += band + gap
            }
        }
        .accessibilityHidden(true)
    }
}

/// Chunky, flat buttons in the brand colors.
struct TapeButtonStyle: ButtonStyle {
    enum Kind { case primary, outline }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(kind == .primary ? Palette.asphalt : Palette.caution)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(kind == .primary ? Palette.caution : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Palette.caution.opacity(kind == .primary ? 0 : 0.7), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// "Take 5": a gentle breathing guide with a countdown.
struct BreathingView: View {
    let endDate: Date
    let onDone: () -> Void
    private let start = Date()
    private static let inhale: Double = 4
    private static let exhale: Double = 6
    // TimelineView never ticks in a non-activating panel of a never-active app;
    // a Timer publisher does.
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    @State private var now = Date()

    var body: some View {
        content(at: now)
            .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
            let elapsed = date.timeIntervalSince(start)
            let remaining = max(0, endDate.timeIntervalSince(date))
            let phase = elapsed.truncatingRemainder(dividingBy: Self.inhale + Self.exhale)
            let inhaling = phase < Self.inhale
            let t = inhaling ? phase / Self.inhale : 1 - (phase - Self.inhale) / Self.exhale
            let eased = 0.5 - cos(t * .pi) / 2

            VStack(spacing: 18) {
                Text(remaining > 0 ? "Take five" : "Welcome back")
                    .font(.system(size: 20, weight: .semibold))
                ZStack {
                    Circle()
                        .fill(Palette.breath.opacity(0.15))
                        .frame(width: 170, height: 170)
                    Circle()
                        .fill(Palette.breath.opacity(0.55))
                        .frame(width: 170, height: 170)
                        .scaleEffect(0.45 + 0.55 * eased)
                    Text(remaining > 0 ? (inhaling ? "Breathe in" : "Breathe out") : "🌿")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                Text(remaining > 0 ? Self.format(remaining) : "How are you feeling about that message now?")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("The message will be right where you left it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Button(remaining > 0 ? "I'm back" : "Done", action: onDone)
            }
            .padding(28)
            .frame(width: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(10)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
