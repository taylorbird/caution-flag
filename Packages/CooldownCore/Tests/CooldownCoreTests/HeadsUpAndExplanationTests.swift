import Foundation
import Testing
@testable import CooldownCore

@Suite("Heads-up level")
struct HeadsUpLevelTests {
    @Test(arguments: [
        (0.0, HeatLevel.calm), (3.9, .calm),
        (4.0, .headsUp), (5.0, .headsUp), (5.9, .headsUp),
        (6.0, .warm), (6.9, .warm),
        (7.0, .hot), (10.0, .hot),
    ])
    func bands(score: Double, expected: HeatLevel) {
        #expect(HeatLevel(score: score) == expected)
    }

    @Test func ordering() {
        #expect(HeatLevel.calm < .headsUp)
        #expect(HeatLevel.headsUp < .warm)
        #expect(HeatLevel.warm < .hot)
    }

    @Test func scoresAreUnchangedOnlyTheLevelMoves() {
        let calm = HeuristicScorer().evaluate("Let's sync on the roadmap.")
        let a = ScoreCombiner().combine(model: ToneResult(heat: 6, category: .frustrated, reason: ""),
                                        heuristic: calm, recentHeatedDrafts: 0)
        #expect(a.score == 6)
        #expect(a.level == .warm)
    }

    @Test func headsUpKeepsItsCategory() {
        let calm = HeuristicScorer().evaluate("Let's sync on the roadmap.")
        let a = ScoreCombiner().combine(model: ToneResult(heat: 4, category: .frustrated, reason: "r"),
                                        heuristic: calm, recentHeatedDrafts: 0)
        #expect(a.level == .headsUp)
        #expect(a.category == .frustrated)
    }
}

@Suite("Why explanation")
struct ExplanationTests {
    let draft = "huh, my bad, I figured it was the cache. I thought those were changes you were pushing."

    @Test func keepsOnlyPhrasesFoundInTheDraft() {
        let kept = ToneExplanation.grounded(
            ["changes you were pushing", "you never listen", "My bad"], in: draft)
        #expect(kept == ["changes you were pushing", "My bad"])
    }

    @Test func stripsQuotesAndCurlyApostrophes() {
        let kept = ToneExplanation.grounded(["\u{201C}I thought those\u{201D}", "'huh,'"], in: draft)
        #expect(kept == ["I thought those", "huh"])
    }

    @Test func capsAtThreeAndDropsDuplicates() {
        let kept = ToneExplanation.grounded(
            ["cache", "CACHE", "figured", "changes", "pushing", "thought"], in: draft)
        #expect(kept == ["cache", "figured", "changes"])
    }

    @Test func parsesOllamaStyleJSON() throws {
        let raw = """
        Sure! ```json
        {"phrases": ["changes you were pushing", "invented phrase"], "howItMightLand": " Could read as a dig. ", "tryInstead": "Lead with thanks."}
        ```
        """
        let e = try ToneResponseParser.parseExplanation(raw, draft: draft)
        #expect(e.phrases == ["changes you were pushing"])
        #expect(e.howItMightLand == "Could read as a dig.")
        #expect(e.tryInstead == "Lead with thanks.")
    }

    @Test func rejectsAnEmptyExplanation() {
        #expect(throws: ToneParseError.self) {
            try ToneResponseParser.parseExplanation(#"{"phrases": [], "howItMightLand": "  "}"#, draft: draft)
        }
    }

    @Test func promptCarriesScoreAndLevelButStaysSeparateFromScoring() {
        let a = ToneAssessment(score: 5, category: .frustrated, reason: "", rewrite: nil, source: .heuristicsOnly)
        let prompt = TonePrompt.explainPrompt(for: draft, assessment: a)
        #expect(prompt.contains("5/10"))
        #expect(prompt.contains("heads-up"))
        #expect(prompt.contains(draft))
        #expect(!TonePrompt.instructions.contains("Why?"))
    }
}
