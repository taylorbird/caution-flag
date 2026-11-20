import Foundation

/// The emotional flavor of a draft. Raw values are what we ask models to emit.
public enum ToneCategory: String, Codable, CaseIterable, Sendable {
    case calm
    case frustrated
    case sarcastic
    case blaming
    case passiveAggressive = "passive-aggressive"
    case venting = "all-caps-or-venting"

    public var displayName: String {
        switch self {
        case .calm: "Calm"
        case .frustrated: "Frustrated"
        case .sarcastic: "Sarcastic"
        case .blaming: "Blaming"
        case .passiveAggressive: "Passive-aggressive"
        case .venting: "Venting"
        }
    }

    /// Maps the many ways a model might spell a category onto our enum.
    public static func normalize(_ raw: String) -> ToneCategory? {
        let key = raw.lowercased().filter(\.isLetter)
        switch key {
        case "calm", "neutral", "positive", "friendly", "none", "polite":
            return .calm
        case "frustrated", "frustration", "angry", "anger", "annoyed", "irritated", "upset", "hostile":
            return .frustrated
        case "sarcastic", "sarcasm":
            return .sarcastic
        case "blaming", "blame", "accusatory", "accusing", "accusation":
            return .blaming
        case "passiveaggressive", "passiveaggression":
            return .passiveAggressive
        default:
            if key.contains("caps") || key.contains("vent") || key.contains("shout") || key.contains("yell") {
                return .venting
            }
            if key.contains("passive") { return .passiveAggressive }
            return nil
        }
    }
}

/// What a model (or the heuristics) thinks about a draft.
public struct ToneResult: Equatable, Sendable {
    public var heat: Double
    public var category: ToneCategory
    public var reason: String
    public var rewrite: String?

    public init(heat: Double, category: ToneCategory, reason: String, rewrite: String? = nil) {
        self.heat = min(10, max(0, heat))
        self.category = category
        self.reason = reason
        self.rewrite = rewrite
    }
}

/// How loudly to flag a draft. Scores are unchanged by the levels; only presentation differs.
/// - headsUp (4–5): a quiet chip that says the draft might be worth a reread.
/// - warm (6): the yellow pill.
/// - hot (7+): the big panel.
public enum HeatLevel: Int, Comparable, Sendable {
    case calm, headsUp, warm, hot

    /// Anything at or above this is flagged at all (the old warm threshold).
    public static let headsUpThreshold = 4.0
    public static let warmThreshold = 6.0
    public static let hotThreshold = 7.0

    public init(score: Double) {
        if score >= Self.hotThreshold { self = .hot }
        else if score >= Self.warmThreshold { self = .warm }
        else if score >= Self.headsUpThreshold { self = .headsUp }
        else { self = .calm }
    }

    /// Plain-language name, as used in prompts and reports.
    public var name: String {
        switch self {
        case .calm: "calm"
        case .headsUp: "heads-up"
        case .warm: "warm"
        case .hot: "hot"
        }
    }

    public static func < (lhs: HeatLevel, rhs: HeatLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The on-demand "Why?" answer: what in the wording drove the rating and how it might land.
/// Asked for only when the user taps Why, never while typing. Held in memory only.
public struct ToneExplanation: Equatable, Sendable {
    /// Short phrases from the draft, verified to appear in it (the model can't invent quotes).
    public var phrases: [String]
    public var howItMightLand: String
    public var tryInstead: String

    public init(phrases: [String], howItMightLand: String, tryInstead: String, draft: String) {
        self.phrases = Self.grounded(phrases, in: draft)
        self.howItMightLand = howItMightLand.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tryInstead = tryInstead.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps up to three phrases that really occur in the draft (ignoring case, curly
    /// quotes and surrounding quote marks), dropping duplicates.
    public static func grounded(_ phrases: [String], in draft: String) -> [String] {
        let haystack = HeuristicScorer.normalize(draft).lowercased()
        var kept: [String] = []
        for raw in phrases {
            let phrase = HeuristicScorer.normalize(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard phrase.count >= 2, haystack.contains(phrase.lowercased()),
                  !kept.contains(where: { $0.lowercased() == phrase.lowercased() }) else { continue }
            kept.append(phrase)
            if kept.count == 3 { break }
        }
        return kept
    }
}

/// Final, combined verdict the UI acts on.
public struct ToneAssessment: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case heuristicsOnly
        case model(String)
        case modelDeclined(String)
    }

    public var score: Double
    public var level: HeatLevel
    public var category: ToneCategory
    public var reason: String
    public var rewrite: String?
    public var source: Source

    public init(score: Double, category: ToneCategory, reason: String, rewrite: String?, source: Source) {
        self.score = min(10, max(0, score))
        self.level = HeatLevel(score: self.score)
        self.category = category
        self.reason = reason
        self.rewrite = rewrite
        self.source = source
    }
}
