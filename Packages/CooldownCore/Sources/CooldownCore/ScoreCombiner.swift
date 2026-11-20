import Foundation

/// Blends the model's opinion with heuristic signals, the user's sensitivity
/// setting, and recent context into one score.
public struct ScoreCombiner: Sendable {
    /// 1 (gentle) … 5 (watchful). 3 is neutral.
    public var sensitivity: Double
    /// Heated drafts in the recent window at which sensitivity rises.
    public var contextThreshold: Int

    public init(sensitivity: Double = 3, contextThreshold: Int = 2) {
        self.sensitivity = min(5, max(1, sensitivity))
        self.contextThreshold = contextThreshold
    }

    public func combine(
        model: ToneResult?,
        modelName: String? = nil,
        modelDeclined: Bool = false,
        heuristic: HeuristicReport,
        recentHeatedDrafts: Int
    ) -> ToneAssessment {
        let h = heuristic.score
        var score: Double
        var category: ToneCategory
        var reason: String
        var rewrite: String?
        let source: ToneAssessment.Source

        if let model {
            // Model leads; heuristics can lift it, never pull it down.
            score = max(model.heat, h * 0.8) + min(h, 4) * 0.3
            category = model.category
            if category == .calm, HeatLevel(score: score) > .calm {
                category = heuristic.suggestedCategory == .calm ? .frustrated : heuristic.suggestedCategory
            }
            reason = model.reason.isEmpty ? Phrasings.reason(for: category) : model.reason
            rewrite = model.rewrite
            source = .model(modelName ?? "model")
        } else if modelDeclined {
            // The on-device model's safety layer declined the text. That
            // usually means strong language, so treat it as at least warm (the pill,
            // not the quieter heads-up chip).
            score = max(h, HeatLevel.warmThreshold)
            category = heuristic.suggestedCategory == .calm ? .venting : heuristic.suggestedCategory
            reason = Phrasings.reason(for: category)
            rewrite = nil
            source = .modelDeclined(modelName ?? "model")
        } else {
            score = h
            category = heuristic.suggestedCategory
            reason = Phrasings.reason(for: category)
            rewrite = nil
            source = .heuristicsOnly
        }

        if score >= 1 {
            score += (sensitivity - 3) * 0.75
        }
        if recentHeatedDrafts >= contextThreshold, score >= 2 {
            score += 1
        }

        let assessment = ToneAssessment(score: score, category: category, reason: reason, rewrite: rewrite, source: source)
        if assessment.level == .calm {
            return ToneAssessment(score: assessment.score, category: .calm, reason: reason, rewrite: nil, source: source)
        }
        return assessment
    }
}

/// Remembers when recent drafts ran hot, so a rough stretch raises sensitivity.
/// Holds timestamps only, never text.
public struct RecentHeatTracker: Sendable {
    public var window: TimeInterval
    private var events: [Date] = []

    public init(window: TimeInterval = 20 * 60) {
        self.window = window
    }

    public mutating func record(at date: Date = Date()) {
        events.append(date)
        prune(now: date)
    }

    public mutating func count(now: Date = Date()) -> Int {
        prune(now: now)
        return events.count
    }

    private mutating func prune(now: Date) {
        events.removeAll { now.timeIntervalSince($0) > window }
    }
}

/// Whether a quick run deserves the credit for a flag. The run is scored together with
/// the draft, but its panel only shows when the run reads clearly hotter than the draft
/// alone; otherwise the draft is judged on its own, as if there were no run.
public enum RunDecision {
    /// How much hotter (in score points) the run must read than the draft alone.
    public static let margin = 1.0

    public static func runApplies(combined: ToneAssessment, alone: ToneAssessment) -> Bool {
        combined.level > .calm && combined.score >= alone.score + margin
    }
}
