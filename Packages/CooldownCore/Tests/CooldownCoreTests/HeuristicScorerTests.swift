import Testing
@testable import CooldownCore

@Suite("HeuristicScorer")
struct HeuristicScorerTests {
    let scorer = HeuristicScorer()

    @Test func shortFriendlyMessageIsObviouslyCalm() {
        let r = scorer.evaluate("Sounds good, thanks!")
        #expect(r.isObviouslyCalm)
        #expect(r.score == 0)
        #expect(r.suggestedCategory == .calm)
    }

    @Test func longCalmMessageIsNotSkipped() {
        let text = "Let's sync on the roadmap and figure out next steps."
        let r = scorer.evaluate(text)
        #expect(r.score == 0)
        #expect(!r.isObviouslyCalm, "long drafts still go to the model")
    }

    @Test func allCapsIsShouting() {
        let r = scorer.evaluate("WHY IS THIS STILL BROKEN")
        #expect(r.has(.allCaps))
        #expect(r.suggestedCategory == .venting)
    }

    @Test func acronymsAreNotShouting() {
        let r = scorer.evaluate("FYI the API and PR are ready for QA, ETA is EOD")
        #expect(!r.has(.allCaps))
        #expect(!r.has(.shoutedWords))
    }

    @Test func twoShoutedWordsCount() {
        let r = scorer.evaluate("I said this NEEDS to be DONE today")
        #expect(r.has(.shoutedWords))
    }

    @Test func repeatedPunctuation() {
        #expect(scorer.evaluate("are you serious??").has(.repeatedPunctuation))
        #expect(scorer.evaluate("seriously?!?!").has(.repeatedPunctuation))
        #expect(!scorer.evaluate("Is that right?").has(.repeatedPunctuation))
    }

    @Test func strongProfanityWeighsMoreThanMild() {
        let strong = scorer.evaluate("what the fuck is this")
        let mild = scorer.evaluate("damn, missed the bus")
        #expect(strong.has(.strongProfanity))
        #expect(mild.has(.mildProfanity))
        #expect(strong.score > mild.score)
    }

    @Test func hellDoesNotMatchHello() {
        #expect(!scorer.evaluate("hello there").has(.mildProfanity))
        #expect(scorer.evaluate("what the hell").has(.mildProfanity))
    }

    @Test func absolutesWithExceptions() {
        #expect(scorer.evaluate("you never listen").has(.absolutes))
        #expect(scorer.evaluate("this always breaks").has(.absolutes))
        #expect(!scorer.evaluate("Never mind, got it").has(.absolutes))
        #expect(!scorer.evaluate("Thanks as always!").has(.absolutes))
    }

    @Test func passiveAggressivePhrases() {
        for phrase in ["Per my last message, it's Friday.", "As I already said, no.", "Just to be clear, I did ask.",
                       "Friendly reminder that this was due.", "For the third time, it's in the doc.", "Re-attaching the file."] {
            #expect(scorer.evaluate(phrase).has(.passiveAggressive), "\(phrase)")
        }
    }

    @Test func curlyApostrophesNormalize() {
        #expect(scorer.evaluate("Why didn\u{2019}t you check first").has(.blaming))
    }

    @Test func blamingPhrases() {
        let r = scorer.evaluate("This is your fault. How many times do I have to say it?")
        #expect(r.has(.blaming))
        #expect(r.suggestedCategory == .blaming)
    }

    @Test func sarcasmMarkers() {
        #expect(scorer.evaluate("Oh great, another outage").has(.sarcasm))
        #expect(scorer.evaluate("Wow. Just wow").has(.sarcasm))
        #expect(scorer.evaluate("sure, love that for us /s").has(.sarcasm))
    }

    @Test func stackedSignalsReachHotAndCap() {
        let r = scorer.evaluate("YOU ALWAYS DO THIS!!! THIS IS YOUR FAULT, FUCKING INCOMPETENT")
        #expect(r.score >= HeatLevel.hotThreshold)
        #expect(r.score <= HeuristicScorer.maxScore)
    }
}

@Suite("Sample harness")
struct SampleHarnessTests {
    let scorer = HeuristicScorer()
    let combiner = ScoreCombiner()

    @Test(arguments: SampleMessages.calm)
    func calmSamplesStayCalm(sample: SampleMessage) {
        let a = combiner.combine(model: nil, heuristic: scorer.evaluate(sample.text), recentHeatedDrafts: 0)
        #expect(a.level == .calm, "\(sample.text) scored \(a.score)")
    }

    @Test(arguments: SampleMessages.heatedObvious)
    func obviousSamplesAreFlaggedWithoutAModel(sample: SampleMessage) {
        let a = combiner.combine(model: nil, heuristic: scorer.evaluate(sample.text), recentHeatedDrafts: 0)
        #expect(a.level > .calm, "\(sample.text) scored \(a.score)")
    }

    @Test(arguments: SampleMessages.heatedSubtle)
    func subtleSamplesAreNotSkipped(sample: SampleMessage) {
        // The model must get a chance at these, so the cheap skip must not fire.
        #expect(!scorer.evaluate(sample.text).isObviouslyCalm)
    }
}

extension SampleMessage: CustomTestStringConvertible {
    public var testDescription: String { text }
}
