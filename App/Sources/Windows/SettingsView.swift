import AppKit
import CooldownCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "slider.horizontal.3") }
            AppsSettings().tabItem { Label("Apps", systemImage: "app.badge") }
            ModelSettings().tabItem { Label("Model", systemImage: "cpu") }
            NotesSettings().tabItem { Label("Notes", systemImage: "heart.text.square") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "lock") }
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var login: LaunchAtLogin

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    Slider(value: $settings.sensitivity, in: 1...5, step: 1) {
                        Text("Sensitivity")
                    } minimumValueLabel: {
                        Text("Gentle")
                    } maximumValueLabel: {
                        Text("Watchful")
                    }
                    Text("Higher means Cool-Down speaks up sooner. It also gets a little more watchful on its own after a few heated drafts in a row.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Text(settings.suppressionReason ?? "Active")
                    Spacer()
                    Button(settings.isSnoozed ? "Resume now" : "Snooze for 1 hour") {
                        settings.snoozeUntil = settings.isSnoozed ? nil : Date().addingTimeInterval(3600)
                    }
                }
                Toggle("Quiet hours", isOn: $settings.quietHoursEnabled)
                if settings.quietHoursEnabled {
                    DatePicker("From", selection: minutesBinding(\.quietStart), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minutesBinding(\.quietEnd), displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { login.isEnabled || login.needsApproval },
                    set: { login.setEnabled($0) }
                ))
                if login.needsApproval {
                    HStack {
                        Text("macOS needs your OK in Login Items.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { login.openLoginItemsSettings() }
                    }
                }
                if let error = login.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
    }

    private func minutesBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(settings[keyPath: keyPath] * 60))
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }
}

private struct AppsSettings: View {
    @EnvironmentObject var settings: SettingsStore

    private var allApps: [WatchedApp] {
        var apps = SettingsStore.suggestedApps
        for app in settings.watchedApps where !apps.contains(where: { $0.bundleID == app.bundleID }) {
            apps.append(app)
        }
        return apps
    }

    var body: some View {
        Form {
            Section {
                ForEach(allApps) { app in
                    Toggle(isOn: Binding(
                        get: { settings.watchedBundleIDs.contains(app.bundleID) },
                        set: { settings.setWatched(app, $0) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Watch these apps")
            } footer: {
                Text("Cool-Down only reads text fields in apps switched on here, and only while that app is in front.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Menu("Add a running app…") {
                    ForEach(runningApps(), id: \.bundleID) { app in
                        Button(app.name) { settings.setWatched(app, true) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runningApps() -> [WatchedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !settings.watchedBundleIDs.contains(id) else { return nil }
                return WatchedApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name < $1.name }
    }
}

private struct ModelSettings: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var analyzers: AnalyzerProvider
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Picker("Analyze with", selection: $settings.analyzerChoice) {
                    ForEach(AnalyzerChoice.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Currently using", value: analyzers.statusText)
                LabeledContent("Apple model", value: analyzers.appleUnavailableReason ?? "Available")
            } footer: {
                Text("Quick checks (caps, punctuation, strong words, phrases like \"per my last message\") always run first. Very short, clearly calm messages skip the model entirely.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ollama") {
                TextField("Address", text: $settings.ollamaURL)
                TextField("Model", text: $settings.ollamaModel)
                HStack {
                    Button(testing ? "Testing…" : "Test connection") {
                        testing = true
                        Task {
                            testResult = await analyzers.testOllama()
                            testing = false
                        }
                    }
                    .disabled(testing)
                    Spacer()
                }
                if let testResult {
                    Text(testResult).font(.caption).textSelection(.enabled)
                }
                Text("Only addresses on this Mac are accepted (localhost, 127.0.0.1, ::1). Cool-Down refuses to send text anywhere else.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.analyzerChoice) { _, _ in analyzers.refresh() }
        .onChange(of: settings.ollamaModel) { _, _ in analyzers.refresh() }
        .onChange(of: settings.ollamaURL) { _, _ in analyzers.refresh() }
    }
}

private struct NotesSettings: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A note to yourself")
                .font(.headline)
            Text("Shown in the larger panel when a draft is running hot. Write it in your own words, from a calm moment. For example: \"Remember: send it tomorrow morning instead.\"")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $settings.personalNotes)
                .font(.body)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
        }
        .padding()
    }
}

private struct PrivacySettings: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("How your words are handled").font(.headline)
                bullet("Drafts are read from the focused text field through macOS Accessibility, only in apps you've switched on, and only while that app is in front.")
                bullet("Password and other secure fields are skipped entirely.")
                bullet("Analysis runs on this Mac: Apple's on-device model, or an Ollama server at a localhost address. Any other address is refused in code.")
                bullet("Draft text lives in memory only. It is never logged, never written to disk, and never sent over the network.")
                bullet("The one exception: when you click \"Save draft for later\", that draft is written to ~/Library/Application Support/Cooldown/drafts.json (readable only by you). Delete drafts any time from Saved Drafts.")
                bullet("Diagnostic logs contain scores and levels, never text.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
