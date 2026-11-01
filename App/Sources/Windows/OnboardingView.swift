import Combine
import CooldownCore
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var analyzers: AnalyzerProvider
    let onDone: () -> Void

    @State private var trusted = AccessibilityPermission.isTrusted
    @State private var ollamaStatus: String?
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Palette.calm)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Cool-Down").font(.title2.weight(.semibold))
                    Text("A quiet pause button for heated messages.").foregroundStyle(.secondary)
                }
            }

            Text("Cool-Down reads the draft you're typing in Slack, checks its tone with a model that runs on this Mac, and gently checks in when a message is running hot. **Nothing you type leaves your computer**, and nothing is saved unless you choose to save a draft.")
                .fixedSize(horizontal: false, vertical: true)

            step(1, title: "Allow Accessibility access", done: trusted) {
                Text("This lets Cool-Down read the text in Slack's message box. It can't see anything else you haven't added to the watch list, and it skips password fields entirely.")
                    .fixedSize(horizontal: false, vertical: true)
                if !trusted {
                    Text("Click the button, find **Cool-Down** (Cooldown) in the list, and switch it on. If it's already on but this still shows as not granted, select it, remove it with **–**, and add it again.")
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.secondary)
                    Button("Open Accessibility Settings") {
                        AccessibilityPermission.requestPrompt()
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }

            step(2, title: "Tone model", done: analyzers.appleUnavailableReason == nil || ollamaStatus?.hasPrefix("Connected. ") == true) {
                if let why = analyzers.appleUnavailableReason {
                    Text("Apple's on-device model isn't available: \(why) You can use Ollama instead (see the README), or run on quick checks alone.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Check Ollama") { Task { ollamaStatus = await analyzers.testOllama() } }
                    if let ollamaStatus { Text(ollamaStatus).font(.callout).foregroundStyle(.secondary) }
                } else {
                    Text("Using Apple's on-device model. It runs entirely on this Mac.")
                }
            }

            step(3, title: "Try it", done: false) {
                Text("Open Slack and type something spicy in any message box. You don't have to send it. After a short pause, the leaf in the menu bar changes color, and a gentle note appears if it's running hot.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            HStack {
                Text("You can reopen this from the menu bar leaf → Setup Guide.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(trusted ? "Done" : "Finish later", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 600)
        .onReceive(poll) { _ in trusted = AccessibilityPermission.isTrusted }
    }

    @ViewBuilder
    private func step<Content: View>(_ n: Int, title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Palette.calm : Color.secondary.opacity(0.2)).frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(n)").font(.system(size: 13, weight: .semibold))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }
    }
}
