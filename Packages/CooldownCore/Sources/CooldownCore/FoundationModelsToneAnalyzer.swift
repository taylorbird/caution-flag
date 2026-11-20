import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct GeneratedScore {
    @Guide(description: "How heated the draft would feel to the recipient. 0 calm, 10 explosive.", .range(0...10))
    var heat: Int

    @Guide(description: "Tone category", .anyOf(["calm", "frustrated", "sarcastic", "blaming", "passive-aggressive", "all-caps-or-venting"]))
    var category: String

    @Guide(description: "One short, warm, non-judgmental sentence about how it might land, addressed to the user as 'you'.")
    var reason: String
}

@available(macOS 26.0, *)
@Generable
struct GeneratedExplanation {
    @Guide(description: "Up to 3 short phrases copied exactly from the draft that most likely drove the rating.", .maximumCount(3))
    var phrases: [String]

    @Guide(description: "One or two short, warm sentences on how those words could read to the recipient, addressed to the user as 'you'.")
    var howItMightLand: String

    @Guide(description: "One short, concrete wording tweak, or that it's probably fine as is.")
    var tryInstead: String
}

/// Apple's on-device model (Apple Intelligence). Text never leaves the Mac.
///
/// Speed: scoring asks only for heat/category/reason (the rewrite is most of the
/// output tokens, so it's a separate call made only when it'll be shown), and a
/// spare session is kept prewarmed so each score skips session setup.
@available(macOS 26.0, *)
public final class FoundationModelsToneAnalyzer: ToneAnalyzer, @unchecked Sendable {
    public var displayName: String { "Apple on-device model" }

    private let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    private let lock = NSLock()
    private var spare: LanguageModelSession?

    public init() {
        refill()
    }

    /// nil when available, otherwise a human-readable reason.
    public static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off in System Settings."
            case .modelNotReady: return "Apple's model is still downloading."
            @unknown default: return "Apple's on-device model isn't available."
            }
        }
    }

    private func refill() {
        let session = LanguageModelSession(model: model, instructions: TonePrompt.instructions)
        session.prewarm()
        lock.withLock { spare = session }
    }

    /// The system unloads the model when idle, so the spare prewarmed at launch or after
    /// the last score may be cold by the time a new draft starts. Warm it again.
    public func prepare() {
        lock.withLock { spare }?.prewarm()
    }

    private func takeSession() -> LanguageModelSession {
        let session = lock.withLock { () -> LanguageModelSession? in
            defer { spare = nil }
            return spare
        } ?? LanguageModelSession(model: model, instructions: TonePrompt.instructions)
        refill() // sessions are single-use (they keep a transcript); stage the next one now
        return session
    }

    public func analyze(_ text: String) async throws -> ToneResult {
        if let why = Self.unavailableReason { throw ToneAnalyzerError.unavailable(why) }
        let session = takeSession()
        do {
            let response = try await session.respond(
                to: TonePrompt.userPrompt(for: text),
                generating: GeneratedScore.self,
                options: GenerationOptions(temperature: 0.2)
            )
            let g = response.content
            let category = ToneCategory.normalize(g.category) ?? (g.heat < 4 ? .calm : .frustrated)
            return ToneResult(
                heat: Double(g.heat),
                category: category,
                reason: g.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
    }

    public func suggestRewrite(_ text: String) async throws -> String? {
        if let why = Self.unavailableReason { throw ToneAnalyzerError.unavailable(why) }
        let session = LanguageModelSession(model: model, instructions: TonePrompt.rewriteInstructions)
        do {
            let response = try await session.respond(
                to: TonePrompt.userPrompt(for: text),
                options: GenerationOptions(temperature: 0.4)
            )
            return TonePrompt.cleanRewrite(response.content)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
    }

    public func explain(_ text: String, assessment: ToneAssessment) async throws -> ToneExplanation {
        if let why = Self.unavailableReason { throw ToneAnalyzerError.unavailable(why) }
        let session = LanguageModelSession(model: model, instructions: TonePrompt.explainInstructions)
        do {
            let response = try await session.respond(
                to: TonePrompt.explainPrompt(for: text, assessment: assessment),
                generating: GeneratedExplanation.self,
                options: GenerationOptions(temperature: 0.3)
            )
            let g = response.content
            return ToneExplanation(phrases: g.phrases, howItMightLand: g.howItMightLand,
                                   tryInstead: g.tryInstead, draft: text)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
    }

    private static func map(_ error: LanguageModelSession.GenerationError) -> ToneAnalyzerError {
        switch error {
        case .guardrailViolation, .refusal: return .declined
        default: return .badResponse(String(describing: error))
        }
    }
}
#endif

/// Availability probe that compiles on every OS.
public enum AppleModelSupport {
    public static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelsToneAnalyzer.unavailableReason
        }
        #endif
        return "Requires macOS 26 or later."
    }

    /// Shared instance, so its prewarmed session is reused across calls.
    nonisolated(unsafe) private static var shared: ToneAnalyzer?
    private static let lock = NSLock()

    public static func makeAnalyzer() -> ToneAnalyzer? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), FoundationModelsToneAnalyzer.unavailableReason == nil {
            return lock.withLock {
                if let shared { return shared }
                let analyzer = FoundationModelsToneAnalyzer()
                shared = analyzer
                return analyzer
            }
        }
        #endif
        return nil
    }
}
