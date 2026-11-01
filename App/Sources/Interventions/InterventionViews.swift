import CooldownCore
import SwiftUI

enum Palette {
    static let calm = Color(red: 0.30, green: 0.69, blue: 0.47)
    static let warm = Color(red: 0.95, green: 0.70, blue: 0.20)
    static let hot = Color(red: 0.89, green: 0.33, blue: 0.30)
    static let breath = Color(red: 0.36, green: 0.62, blue: 0.75)
}

/// The small, unobtrusive "this is reading a little hot" nudge.
struct PillView: View {
    let message: String
    let canExpand: Bool
    let onExpand: () -> Void
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

/// The larger panel for drafts running hot.
struct HotPanelView: View {
    @ObservedObject var model: PanelModel
    let onCopy: (String) -> Void
    let onTakeFive: () -> Void
    let onSave: () -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(Palette.hot).frame(width: 9, height: 9)
                Text(model.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let assessment = model.assessment {
                Text(assessment.reason)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if assessment.rewrite == nil && model.rewriteLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Drafting a calmer version…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                if let rewrite = assessment.rewrite {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A calmer version")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(rewrite)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(model.copied ? "Copied" : "Copy") { onCopy(rewrite) }
                            .controlSize(.small)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.calm.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if !model.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A note from you")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(model.notes)
                        .font(.system(size: 13).italic())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.breath.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }

            switch model.saveState {
            case .idle:
                HStack(spacing: 8) {
                    Button("Take 5", action: onTakeFive)
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.breath)
                    Button("Save draft for later", action: onSave)
                    Spacer()
                    Button("I'm fine, dismiss", action: onDismiss)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            case .saved:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved privately on this Mac. Clear it from the message box too?")
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Clear it", action: onClear)
                        Button("Keep it there", action: onDismiss)
                    }
                }
            case .cleared:
                Text("Cleared. It's waiting in Saved Drafts whenever you're ready.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.hot.opacity(0.35), lineWidth: 1))
        .padding(10)
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
