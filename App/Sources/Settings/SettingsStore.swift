import Combine
import CooldownCore
import Foundation

struct WatchedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

enum AnalyzerChoice: String, CaseIterable, Identifiable, Codable {
    case automatic, apple, ollama, heuristicsOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Automatic (Apple, then Ollama)"
        case .apple: "Apple on-device model"
        case .ollama: "Ollama"
        case .heuristicsOnly: "Quick checks only (no model)"
        }
    }
}

/// User preferences, persisted in UserDefaults. Never holds message text
/// (personal notes are the user's own words about themselves, not drafts).
@MainActor
final class SettingsStore: ObservableObject {
    static let slack = WatchedApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    static let suggestedApps: [WatchedApp] = [
        slack,
        WatchedApp(bundleID: "dev.tbird.echo", name: "Echo"),
        WatchedApp(bundleID: "com.apple.mail", name: "Mail"),
        WatchedApp(bundleID: "com.apple.MobileSMS", name: "Messages"),
        WatchedApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams"),
        WatchedApp(bundleID: "com.apple.Safari", name: "Safari"),
        WatchedApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
        WatchedApp(bundleID: "company.thebrowser.Browser", name: "Arc"),
        WatchedApp(bundleID: "org.mozilla.firefox", name: "Firefox"),
        WatchedApp(bundleID: "com.hnc.Discord", name: "Discord"),
    ]

    private let defaults: UserDefaults
    var onWatchedAppsChange: ((Set<String>) -> Void)?

    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: Keys.sensitivity) } }
    @Published var watchedApps: [WatchedApp] {
        didSet {
            defaults.set(try? JSONEncoder().encode(watchedApps), forKey: Keys.watchedApps)
            onWatchedAppsChange?(watchedBundleIDs)
        }
    }
    @Published var analyzerChoice: AnalyzerChoice { didSet { defaults.set(analyzerChoice.rawValue, forKey: Keys.analyzer) } }
    @Published var ollamaURL: String { didSet { defaults.set(ollamaURL, forKey: Keys.ollamaURL) } }
    @Published var ollamaModel: String { didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) } }
    @Published var quietHoursEnabled: Bool { didSet { defaults.set(quietHoursEnabled, forKey: Keys.quietEnabled) } }
    /// Minutes after midnight.
    @Published var quietStart: Int { didSet { defaults.set(quietStart, forKey: Keys.quietStart) } }
    @Published var quietEnd: Int { didSet { defaults.set(quietEnd, forKey: Keys.quietEnd) } }
    @Published var snoozeUntil: Date? { didSet { defaults.set(snoozeUntil, forKey: Keys.snoozeUntil) } }
    @Published var personalNotes: String { didSet { defaults.set(personalNotes, forKey: Keys.notes) } }
    @Published var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Keys.onboarded) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sensitivity = defaults.object(forKey: Keys.sensitivity) as? Double ?? 3
        watchedApps = (defaults.data(forKey: Keys.watchedApps)).flatMap { try? JSONDecoder().decode([WatchedApp].self, from: $0) }
            ?? [Self.slack]
        analyzerChoice = defaults.string(forKey: Keys.analyzer).flatMap(AnalyzerChoice.init(rawValue:)) ?? .automatic
        ollamaURL = defaults.string(forKey: Keys.ollamaURL) ?? OllamaToneAnalyzer.defaultURL.absoluteString
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? OllamaToneAnalyzer.defaultModel
        quietHoursEnabled = defaults.bool(forKey: Keys.quietEnabled)
        quietStart = defaults.object(forKey: Keys.quietStart) as? Int ?? 21 * 60
        quietEnd = defaults.object(forKey: Keys.quietEnd) as? Int ?? 7 * 60
        snoozeUntil = defaults.object(forKey: Keys.snoozeUntil) as? Date
        personalNotes = defaults.string(forKey: Keys.notes) ?? ""
        onboardingCompleted = defaults.bool(forKey: Keys.onboarded)
    }

    var watchedBundleIDs: Set<String> { Set(watchedApps.map(\.bundleID)) }

    var isSnoozed: Bool {
        guard let until = snoozeUntil else { return false }
        return until > Date()
    }

    func isQuietHours(at date: Date = Date()) -> Bool {
        guard quietHoursEnabled else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let now = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if quietStart == quietEnd { return false }
        if quietStart < quietEnd { return now >= quietStart && now < quietEnd }
        return now >= quietStart || now < quietEnd // spans midnight
    }

    /// Why interventions are paused right now, if they are.
    var suppressionReason: String? {
        if isSnoozed, let until = snoozeUntil {
            return "Snoozed until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if isQuietHours() { return "Quiet hours" }
        return nil
    }

    func setWatched(_ app: WatchedApp, _ on: Bool) {
        if on, !watchedApps.contains(app) { watchedApps.append(app) }
        if !on { watchedApps.removeAll { $0.bundleID == app.bundleID } }
    }

    private enum Keys {
        static let sensitivity = "sensitivity"
        static let watchedApps = "watchedApps"
        static let analyzer = "analyzerChoice"
        static let ollamaURL = "ollamaURL"
        static let ollamaModel = "ollamaModel"
        static let quietEnabled = "quietHoursEnabled"
        static let quietStart = "quietStart"
        static let quietEnd = "quietEnd"
        static let snoozeUntil = "snoozeUntil"
        static let notes = "personalNotes"
        static let onboarded = "onboardingCompleted"
    }
}
