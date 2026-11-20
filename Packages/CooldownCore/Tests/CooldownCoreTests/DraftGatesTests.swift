import Foundation
import Testing
@testable import CooldownCore

@Suite("Draft gates")
struct DraftGatesTests {
    let scorer = HeuristicScorer()

    func model(_ heat: Double) -> ToneAssessment {
        ScoreCombiner().combine(model: ToneResult(heat: heat, category: .frustrated, reason: "r"),
                                heuristic: scorer.evaluate("plain words"), recentHeatedDrafts: 0)
    }

    @Test func shortUnfinishedDraftTopsOutAtHeadsUp() {
        // Paraphrase of a report: half a sentence, flagged warm mid-typing.
        let draft = "honestly this feels like polish stuff, so"
        let capped = DraftGates.capShortDraft(model(6), draft: draft, heuristic: scorer.evaluate(draft))
        #expect(capped.level == .headsUp)
        let hot = DraftGates.capShortDraft(model(8), draft: draft, heuristic: scorer.evaluate(draft))
        #expect(hot.level == .headsUp)
    }

    @Test func clearSignalsAreNotCapped() {
        let draft = "this is stupid, do your job"
        let a = DraftGates.capShortDraft(model(8), draft: draft, heuristic: scorer.evaluate(draft))
        #expect(a.level == .hot)
    }

    @Test func declinedDraftsStayWarm() {
        let draft = "short one"
        let declined = ScoreCombiner().combine(model: nil, modelDeclined: true,
                                               heuristic: scorer.evaluate(draft), recentHeatedDrafts: 0)
        #expect(DraftGates.capShortDraft(declined, draft: draft, heuristic: scorer.evaluate(draft)).level == .warm)
    }

    @Test func longDraftsAreNotCapped() {
        let draft = String(repeating: "a calm sentence that keeps going ", count: 3)
        let a = DraftGates.capShortDraft(model(6), draft: draft, heuristic: scorer.evaluate(draft))
        #expect(a.level == .warm)
    }

    @Test func headsUpAndBelowPassThrough() {
        let draft = "short"
        #expect(DraftGates.capShortDraft(model(5), draft: draft, heuristic: scorer.evaluate(draft)).score == 5)
    }

    @Test func loneFourIsHeld() {
        #expect(!DraftGates.showsHeadsUp(score: 4, previousModelScore: nil))
        #expect(!DraftGates.showsHeadsUp(score: 4, previousModelScore: 3))
    }

    @Test func fourAfterFourOrAnyFiveShows() {
        #expect(DraftGates.showsHeadsUp(score: 4, previousModelScore: 4))
        #expect(DraftGates.showsHeadsUp(score: 4.5, previousModelScore: 6))
        #expect(DraftGates.showsHeadsUp(score: 5, previousModelScore: nil))
    }
}
