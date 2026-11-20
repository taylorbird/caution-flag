import Foundation
import Testing
@testable import CooldownCore

@Suite("Quick-run speed check")
struct RunTuningTests {
    @Test func defaultIsTighterThanTheOriginal() {
        let normal = BurstTracker.tuning(level: 3)
        let original = BurstTracker.tuning(level: 5)
        #expect(normal.maxGap < original.maxGap)
        #expect(normal.maxLength < original.maxLength)
        #expect(normal.minPriorSends > original.minPriorSends)
        #expect(original == BurstTracker.Tuning(maxGap: 60, maxLength: 200, minPriorSends: 2))
    }

    @Test func levelsGetMoreWatchfulMonotonically() {
        let tunings = (1...5).map { BurstTracker.tuning(level: Double($0)) }
        for (a, b) in zip(tunings, tunings.dropFirst()) {
            #expect(a.maxGap <= b.maxGap)
            #expect(a.maxLength <= b.maxLength)
            #expect(a.minPriorSends >= b.minPriorSends)
        }
    }

    @Test func outOfRangeLevelsClamp() {
        #expect(BurstTracker.tuning(level: 0) == BurstTracker.tuning(level: 1))
        #expect(BurstTracker.tuning(level: 9) == BurstTracker.tuning(level: 5))
    }

    @Test func normalPaceNoLongerCountsAtTheDefault() {
        // Paraphrase of a real case: a reply every ~11 s, one of them long.
        var t = BurstTracker(level: 3)
        let start = Date()
        t.recordSend("kk, sounds good", at: start)
        t.recordSend("on it now", at: start.addingTimeInterval(11))
        t.recordSend(String(repeating: "a longer reply about the photo and the story behind it ", count: 3),
                     at: start.addingTimeInterval(47))
        t.recordSend("ha, fair", at: start.addingTimeInterval(56))
        #expect(t.context(now: start.addingTimeInterval(80)) == nil)
    }

    @Test func rapidFireStillCountsAtTheDefault() {
        var t = BurstTracker(level: 3)
        let start = Date()
        for (i, msg) in ["no", "that's not what I said", "read it again", "seriously"].enumerated() {
            t.recordSend(msg, at: start.addingTimeInterval(Double(i) * 6))
        }
        #expect(t.context(now: start.addingTimeInterval(25))?.count == 4)
    }

    @Test func configureKeepsTheCurrentRun() {
        var t = BurstTracker(level: 5)
        let start = Date()
        t.recordSend("one", at: start)
        t.recordSend("two", at: start.addingTimeInterval(5))
        t.configure(level: 3)
        t.recordSend("three", at: start.addingTimeInterval(10))
        #expect(t.context(now: start.addingTimeInterval(12))?.count == 3)
    }
}

@Suite("Run decision")
struct RunDecisionTests {
    func assessment(_ score: Double) -> ToneAssessment {
        ToneAssessment(score: score, category: .frustrated, reason: "", rewrite: nil, source: .heuristicsOnly)
    }

    @Test func runMustReadClearlyHotterThanTheDraft() {
        #expect(RunDecision.runApplies(combined: assessment(8), alone: assessment(3)))
        #expect(RunDecision.runApplies(combined: assessment(6), alone: assessment(5)))
        #expect(!RunDecision.runApplies(combined: assessment(6), alone: assessment(5.5)))
        #expect(!RunDecision.runApplies(combined: assessment(7), alone: assessment(7)))
    }

    @Test func calmRunNeverApplies() {
        #expect(!RunDecision.runApplies(combined: assessment(3), alone: assessment(0)))
    }
}

@Suite("Capture cleanup")
struct CaptureCleanupTests {
    @Test func stripsMentionChipLabels() {
        #expect(CaptureCleanup.clean("kk, so @sam Remove mention link can you look") == "kk, so @sam can you look")
    }

    @Test func caseInsensitiveAndKeepsLineBreaks() {
        #expect(CaptureCleanup.clean("hi @sam remove MENTION link\nsecond line") == "hi @sam\nsecond line")
    }

    @Test func leavesNormalTextAlone() {
        let text = "I'll remove the link from the doc  later"
        #expect(CaptureCleanup.clean(text) == text)
    }
}
