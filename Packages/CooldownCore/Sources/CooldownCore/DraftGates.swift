import Foundation

/// Presentation gates applied after scoring, from Not heated reports (2026-11-20).
/// They never change how the model is asked; they decide how loudly to show a score.
public enum DraftGates {
    /// Drafts shorter than this are often still being written.
    public static let shortDraftLimit = 60

    /// A short draft with no heuristic signal tops out at heads-up: half a sentence
    /// ending in "so" read as warm to the model while still being typed. Clear signals
    /// (insults, profanity, shouting, blame phrases) are exempt and keep their level, and
    /// so are drafts the model declined (deliberately warm; see ScoreCombiner).
    public static func capShortDraft(_ assessment: ToneAssessment, draft: String,
                                     heuristic: HeuristicReport) -> ToneAssessment {
        let length = draft.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard (length < shortDraftLimit), heuristic.signals.isEmpty, (assessment.level > .headsUp) else { return assessment }
        if case .modelDeclined = assessment.source { return assessment }
        return ToneAssessment(score: min(assessment.score, HeatLevel.warmThreshold - 0.1),
                              category: assessment.category, reason: assessment.reason,
                              rewrite: nil, source: assessment.source)
    }

    /// Score-4 hysteresis: a lone 4 is the model's "a little terse" wobble on plain
    /// messages. Heads-up shows at 5+, or at 4 when the previous score for this draft
    /// was also 4+.
    public static func showsHeadsUp(score: Double, previousModelScore: Double?) -> Bool {
        score >= HeatLevel.headsUpThreshold + 1 || (previousModelScore ?? 0) >= HeatLevel.headsUpThreshold
    }
}
