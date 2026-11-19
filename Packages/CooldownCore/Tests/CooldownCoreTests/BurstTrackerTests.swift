import Foundation
import Testing
@testable import CooldownCore

@Suite("BurstTracker")
struct BurstTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func noBurstUntilEnoughSends() {
        var b = BurstTracker()
        #expect(b.context(now: t0) == nil)
        b.recordSend("though this makes no sense", at: t0)
        #expect(b.context(now: t0.addingTimeInterval(5)) == nil)
        b.recordSend("we have no reports", at: t0.addingTimeInterval(10))
        #expect(b.context(now: t0.addingTimeInterval(15)) == ["though this makes no sense", "we have no reports"])
    }

    @Test func longPauseEndsBurst() {
        var b = BurstTracker(maxGap: 60)
        b.recordSend("one", at: t0)
        b.recordSend("two", at: t0.addingTimeInterval(10))
        #expect(b.context(now: t0.addingTimeInterval(71)) == nil)
        // And the old sends don't come back with a new one.
        b.recordSend("three", at: t0.addingTimeInterval(80))
        #expect(b.context(now: t0.addingTimeInterval(81)) == nil)
    }

    @Test func longMessageEndsBurst() {
        var b = BurstTracker(maxLength: 20)
        b.recordSend("short", at: t0)
        b.recordSend("short again", at: t0.addingTimeInterval(5))
        b.recordSend(String(repeating: "x", count: 21), at: t0.addingTimeInterval(10))
        #expect(b.context(now: t0.addingTimeInterval(11)) == nil)
        #expect(b.sendCount == 0)
    }

    @Test func oldSendsAgeOutOfWindow() {
        var b = BurstTracker(window: 60, maxGap: 30)
        for i in 0..<5 { b.recordSend("m\(i)", at: t0.addingTimeInterval(Double(i) * 25)) }
        // Sends at 0, 25, 50, 75, 100; at 110 only those within 60 s remain.
        #expect(b.context(now: t0.addingTimeInterval(110)) == ["m2", "m3", "m4"])
    }

    @Test func keepsOnlyMostRecent() {
        var b = BurstTracker(maxKept: 3)
        for i in 0..<5 { b.recordSend("m\(i)", at: t0.addingTimeInterval(Double(i))) }
        #expect(b.context(now: t0.addingTimeInterval(6)) == ["m2", "m3", "m4"])
    }

    @Test func blankSendResets() {
        var b = BurstTracker()
        b.recordSend("one", at: t0)
        b.recordSend("two", at: t0.addingTimeInterval(1))
        b.recordSend("   ", at: t0.addingTimeInterval(2))
        #expect(b.context(now: t0.addingTimeInterval(3)) == nil)
    }

    @Test func combinedJoinsOnePerLine() {
        #expect(BurstTracker.combined(["a", "b"], draft: " c \n") == "a\nb\nc")
    }
}
