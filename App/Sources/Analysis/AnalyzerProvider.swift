import CooldownCore
import Foundation

/// Picks the analyzer the settings ask for and tracks whether it's working.
@MainActor
final class AnalyzerProvider: ObservableObject {
    private let settings: SettingsStore
    /// Shown in the menu and settings, e.g. "Apple on-device model" or a problem.
    @Published private(set) var statusText = "Starting…"
    @Published private(set) var lastProblem: String?

    init(settings: SettingsStore) {
        self.settings = settings
        statusText = describeCurrent()
    }

    var appleUnavailableReason: String? { AppleModelSupport.unavailableReason }

    func currentAnalyzer() -> ToneAnalyzer? {
        switch settings.analyzerChoice {
        case .heuristicsOnly:
            return nil
        case .apple:
            return AppleModelSupport.makeAnalyzer()
        case .ollama:
            return makeOllama()
        case .automatic:
            return AppleModelSupport.makeAnalyzer() ?? makeOllama()
        }
    }

    func makeOllama() -> OllamaToneAnalyzer? {
        guard let url = URL(string: settings.ollamaURL) else { return nil }
        return try? OllamaToneAnalyzer(baseURL: url, model: settings.ollamaModel)
    }

    func noteSuccess() {
        lastProblem = nil
        statusText = describeCurrent()
    }

    func noteFailure(_ error: Error) {
        let message: String
        if let e = error as? ToneAnalyzerError {
            message = e.description
        } else if (error as? URLError)?.code == .cannotConnectToHost {
            message = "Ollama isn't running."
        } else {
            message = error.localizedDescription
        }
        lastProblem = message
        statusText = "Quick checks only (\(message))"
    }

    func describeCurrent() -> String {
        if let analyzer = currentAnalyzer() { return analyzer.displayName }
        switch settings.analyzerChoice {
        case .heuristicsOnly: return "Quick checks only"
        case .apple: return "Quick checks only (\(appleUnavailableReason ?? "Apple model unavailable"))"
        case .ollama, .automatic: return "Quick checks only (invalid Ollama address)"
        }
    }

    func refresh() {
        statusText = describeCurrent()
    }

    /// For the Settings "Test connection" button.
    func testOllama() async -> String {
        guard let url = URL(string: settings.ollamaURL) else { return "That address doesn't look valid." }
        guard LoopbackGuard.isLoopback(url) else { return "Only addresses on this Mac (localhost / 127.0.0.1) are allowed." }
        guard let ollama = makeOllama() else { return "Couldn't create the Ollama client." }
        do {
            let models = try await ollama.installedModels()
            if models.isEmpty { return "Connected, but no models are installed. Run: ollama pull \(settings.ollamaModel)" }
            let hasModel = models.contains { $0 == settings.ollamaModel || $0.hasPrefix(settings.ollamaModel + ":") }
            return hasModel
                ? "Connected. \(settings.ollamaModel) is ready."
                : "Connected, but \(settings.ollamaModel) isn't installed. Run: ollama pull \(settings.ollamaModel)\nInstalled: \(models.joined(separator: ", "))"
        } catch {
            return "Couldn't reach Ollama at \(url.absoluteString). Is `ollama serve` running?"
        }
    }
}
