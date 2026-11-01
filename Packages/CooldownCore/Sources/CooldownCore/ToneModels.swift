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

public enum HeatLevel: Int, Comparable, Sendable {
    case calm, warm, hot

    public static let warmThreshold = 4.0
    public static let hotThreshold = 7.0

    public init(score: Double) {
        if score >= Self.hotThreshold { self = .hot }
        else if score >= Self.warmThreshold { self = .warm }
        else { self = .calm }
    }

    public static func < (lhs: HeatLevel, rhs: HeatLevel) -> Bool { lhs.rawValue < rhs.rawValue }
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
