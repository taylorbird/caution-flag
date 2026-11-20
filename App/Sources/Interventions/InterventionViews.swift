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

/// The small nudge, in the caution-tape look. Two styles share one window:
/// - heads-up: low-key asphalt chip, a quiet outline. "Worth a reread", not an alarm.
/// - warm: the same chip with a strip of hazard tape and a brighter edge.
/// Why? is the most prominent control on both.
struct NudgeView: View {
    @ObservedObject var model: NudgeModel
    let onWhy: () -> Void
    let onSoften: () -> Void
    let onNotHeated: () -> Void
    let onJustThisOne: () -> Void
    let onClose: () -> Void

    private var isWarm: Bool { model.style == .warm }
    private static let corner: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.notedMisread {
                Text("Noted. Thanks.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HotPanelView.ink)
                    .padding(.vertical, 2)
            } else {
                row
                if let count = model.runCount {
                    RunNote(count: count, onJustThisOne: onJustThisOne)
                        .padding(.top, 6)
                }
                if model.why != .idle {
                    WhyCard(state: model.why, onNotHeated: onNotHeated)
                        .frame(width: 380)
                        .padding(.top, 10)
                }
            }
        }
        .padding(.leading, isWarm ? 22 : 14)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
        .background(Palette.asphalt)
        .overlay(alignment: .leading) {
            if isWarm { HazardTape().frame(width: 8) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(Palette.caution.opacity(isWarm ? 0.9 : 0.4), lineWidth: isWarm ? 1.5 : 1)
        )
        .padding(8)
    }

    private var row: some View {
        HStack(spacing: 10) {
            if !isWarm {
                Circle()
                    .strokeBorder(Palette.caution, lineWidth: 1.5)
                    .background(Circle().fill(Palette.caution.opacity(0.35)).padding(3))
                    .frame(width: 11, height: 11)
            }
            Text(model.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HotPanelView.ink)
                .fixedSize()
            if model.why == .idle || isFailed {
                WhyButton(action: onWhy)
            }
            if isWarm {
                Button("Soften", action: onSoften)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.caution)
                    .help("Open the full panel: a calmer version, Take 5, Save for later")
            }
            if model.why == .idle || isFailed {
                Button("Not heated", action: onNotHeated)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HotPanelView.ink.opacity(0.5))
                    .help("This one's fine. Saves it on this Mac so the tuning can improve.")
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HotPanelView.ink.opacity(0.55))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Not this time")
        }
    }

    private var isFailed: Bool {
        if case .failed = model.why { return true }
        return false
    }
}

/// Says plainly when a flag comes from a quick run of messages, not just this draft,
/// and offers to judge this draft on its own.
struct RunNote: View {
    let count: Int
    let onJustThisOne: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.caution.opacity(0.8))
            Text("Read with your last \(count) message\(count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HotPanelView.ink.opacity(0.7))
                .lineLimit(1)
            Button("Just this one", action: onJustThisOne)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.caution)
                .fixedSize()
                .help("Judge this draft on its own, without the messages you just sent.")
            Spacer(minLength: 0)
        }
    }
}

/// The "Why?" control: filled caution yellow so it's the first thing the eye finds.
struct WhyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Why?", systemImage: "questionmark.bubble.fill")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.asphalt)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Palette.caution, in: Capsule())
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .help("Ask the on-device model what in the wording drove this. Nothing leaves this Mac.")
    }
}

/// The on-demand explanation: the phrases that drove the rating, how they might land,
/// and one small tweak. Shared by the nudge and the hot panel.
struct WhyCard: View {
    let state: WhyState
    /// Nil hides the "Not heated" link (the hot panel has its own).
    var onNotHeated: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("WHY IT FLAGGED")
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Palette.caution)
            switch state {
            case .idle:
                EmptyView()
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Palette.caution)
                    Text("Taking a closer look…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(HotPanelView.ink.opacity(0.65))
                }
            case .ready(let why):
                if !why.phrases.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(why.phrases, id: \.self) { phrase in
                            Text("\u{201C}\(phrase)\u{201D}")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Palette.caution)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Palette.caution.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text(why.howItMightLand)
                    .font(.system(size: 13))
                    .foregroundStyle(HotPanelView.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                if !why.tryInstead.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("TRY")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Palette.asphalt)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Palette.caution, in: RoundedRectangle(cornerRadius: 4))
                        Text(why.tryInstead)
                            .font(.system(size: 13))
                            .foregroundStyle(HotPanelView.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                footer
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(HotPanelView.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("A second look from the same local model. It can misread too.")
                .font(.system(size: 11))
                .foregroundStyle(HotPanelView.ink.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            if let onNotHeated {
                Spacer(minLength: 4)
                Button("Not heated", action: onNotHeated)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(HotPanelView.ink.opacity(0.6))
                    .help("This one's fine. Saves it on this Mac so the tuning can improve.")
            }
        }
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
    let onWhy: () -> Void
    let onJustThisOne: () -> Void
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
            if let count = model.runCount {
                RunNote(count: count, onJustThisOne: onJustThisOne)
            }
            if let assessment = model.assessment {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(assessment.reason)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Self.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.why == .idle || isWhyFailed {
                        WhyButton(action: onWhy)
                    }
                }
                if model.why != .idle {
                    WhyCard(state: model.why)
                }

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

    private var isWhyFailed: Bool {
        if case .failed = model.why { return true }
        return false
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

/// "Take 5": a gentle breathing guide with a countdown, in the caution-tape look.
struct BreathingView: View {
    let endDate: Date
    let onDone: () -> Void
    private let start = Date()
    private static let inhale: Double = 4
    private static let exhale: Double = 6
    private static let corner: CGFloat = 16
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
        let done = remaining <= 0

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: done ? "flag.checkered" : "stopwatch.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(done ? "Welcome back" : "Take five")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                Spacer(minLength: 0)
                Text(done ? "" : Self.format(remaining))
                    .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(Palette.asphalt)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(ZStack { Palette.caution; SpeedStripes(color: Palette.asphalt.opacity(0.06)) })
            HazardTape().frame(height: 10)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .strokeBorder(Palette.caution.opacity(0.35), lineWidth: 2)
                        .frame(width: 170, height: 170)
                    Circle()
                        .fill(Palette.caution.opacity(done ? 0.25 : 0.85))
                        .frame(width: 170, height: 170)
                        .scaleEffect(done ? 0.55 : 0.45 + 0.55 * eased)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(Palette.caution)
                    }
                }
                .padding(.top, 6)
                Text(done ? "How are you feeling about that message now?" : (inhaling ? "Breathe in" : "Breathe out"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(HotPanelView.ink)
                    .multilineTextAlignment(.center)
                Text("The message will be right where you left it.")
                    .font(.system(size: 12))
                    .foregroundStyle(HotPanelView.ink.opacity(0.5))
                Button(done ? "Done" : "I'm back", action: onDone)
                    .buttonStyle(TapeButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .frame(width: 320)
        .background(Palette.asphalt)
        .clipShape(RoundedRectangle(cornerRadius: Self.corner))
        .overlay(RoundedRectangle(cornerRadius: Self.corner).strokeBorder(Palette.caution.opacity(0.9), lineWidth: 2))
        .padding(10)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
