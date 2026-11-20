import Foundation
import Testing
@testable import CooldownCore

@Suite("ToneResponseParser")
struct ToneResponseParserTests {
    @Test func plainJSON() throws {
        let r = try ToneResponseParser.parse(#"{"heat": 7, "category": "blaming", "reason": "Reads as blame.", "rewrite": "Can we look at this together?"}"#)
        #expect(r.heat == 7)
        #expect(r.category == .blaming)
        #expect(r.reason == "Reads as blame.")
        #expect(r.rewrite == "Can we look at this together?")
    }

    @Test func fencedJSONWithProse() throws {
        let raw = """
        Sure! Here's my assessment:
        ```json
        {"heat": 5, "category": "passive-aggressive", "reason": "x", "rewrite": "y"}
        ```
        Hope that helps.
        """
        let r = try ToneResponseParser.parse(raw)
        #expect(r.heat == 5)
        #expect(r.category == .passiveAggressive)
    }

    @Test func bracesInsideStringsDoNotConfuseExtraction() throws {
        let r = try ToneResponseParser.parse(#"{"heat": 2, "category": "calm", "reason": "uses {braces} fine", "rewrite": ""}"#)
        #expect(r.reason == "uses {braces} fine")
        #expect(r.rewrite == nil)
    }

    @Test(arguments: [("7", 7.0), ("7/10", 7.0), ("heat 6.5", 6.5), ("14", 10.0), ("-3", 3.0)])
    func stringHeat(raw: String, expected: Double) throws {
        let r = try ToneResponseParser.parse(#"{"heat": "\#(raw)", "category": "frustrated", "reason": ""}"#)
        #expect(r.heat == expected)
    }

    @Test func numericHeatIsClamped() throws {
        #expect(try ToneResponseParser.parse(#"{"heat": 42, "category": "calm"}"#).heat == 10)
        #expect(try ToneResponseParser.parse(#"{"heat": -2, "category": "calm"}"#).heat == 0)
    }

    @Test(arguments: [
        ("passive_aggressive", ToneCategory.passiveAggressive), ("Passive Aggressive", .passiveAggressive),
        ("ALL CAPS / venting", .venting), ("venting", .venting), ("all-caps-or-venting", .venting),
        ("Sarcasm", .sarcastic), ("accusatory", .blaming), ("neutral", .calm), ("angry", .frustrated),
    ])
    func categorySpellings(raw: String, expected: ToneCategory) throws {
        let r = try ToneResponseParser.parse(#"{"heat": 5, "category": "\#(raw)"}"#)
        #expect(r.category == expected)
    }

    @Test func unknownCategoryFallsBackOnHeat() throws {
        #expect(try ToneResponseParser.parse(#"{"heat": 1, "category": "whimsical"}"#).category == .calm)
        #expect(try ToneResponseParser.parse(#"{"heat": 8, "category": "whimsical"}"#).category == .frustrated)
    }

    @Test func alternateKeysAndNullRewrite() throws {
        let r = try ToneResponseParser.parse(#"{"Heat_Score": 6, "tone": "sarcastic", "explanation": "e", "calmer_rewrite": null}"#)
        #expect(r.heat == 6)
        #expect(r.category == .sarcastic)
        #expect(r.reason == "e")
        #expect(r.rewrite == nil)
    }

    @Test func placeholderRewritesBecomeNil() throws {
        for placeholder in ["none", "N/A", "  "] {
            let r = try ToneResponseParser.parse(#"{"heat": 2, "category": "calm", "rewrite": "\#(placeholder)"}"#)
            #expect(r.rewrite == nil)
        }
    }

    @Test func failures() {
        #expect(throws: ToneParseError.noJSON) { try ToneResponseParser.parse("I can't help with that.") }
        #expect(throws: ToneParseError.invalidJSON) { try ToneResponseParser.parse("{heat: seven}") }
        #expect(throws: ToneParseError.missingHeat) { try ToneResponseParser.parse(#"{"category": "calm"}"#) }
    }
}

@Suite("ScoreCombiner")
struct ScoreCombinerTests {
    let scorer = HeuristicScorer()
    let calmReport = HeuristicScorer().evaluate("Let's sync on the roadmap.")

    @Test func modelOnly() {
        let a = ScoreCombiner().combine(model: ToneResult(heat: 5, category: .frustrated, reason: "r"),
                                        heuristic: calmReport, recentHeatedDrafts: 0)
        #expect(a.score == 5)
        #expect(a.level == .headsUp)
        #expect(a.reason == "r")
    }

    @Test func heuristicsLiftModelButNeverLowerIt() {
        let hot = scorer.evaluate("You always do this!!!")
        let lifted = ScoreCombiner().combine(model: ToneResult(heat: 5, category: .blaming, reason: ""),
                                             heuristic: hot, recentHeatedDrafts: 0)
        #expect(lifted.score > 5)
        let calm = ScoreCombiner().combine(model: ToneResult(heat: 8, category: .blaming, reason: ""),
                                           heuristic: calmReport, recentHeatedDrafts: 0)
        #expect(calm.score == 8)
    }

    @Test func sensitivityShiftsScore() {
        let model = ToneResult(heat: 4, category: .frustrated, reason: "")
        let gentle = ScoreCombiner(sensitivity: 1).combine(model: model, heuristic: calmReport, recentHeatedDrafts: 0)
        let watchful = ScoreCombiner(sensitivity: 5).combine(model: model, heuristic: calmReport, recentHeatedDrafts: 0)
        #expect(gentle.level == .calm)
        #expect(watchful.score == 5.5)
    }

    @Test func sensitivityNeverFlagsZeroHeat() {
        let a = ScoreCombiner(sensitivity: 5).combine(model: ToneResult(heat: 0, category: .calm, reason: ""),
                                                      heuristic: calmReport, recentHeatedDrafts: 5)
        #expect(a.level == .calm)
    }

    @Test func recentHeatRaisesSensitivity() {
        let model = ToneResult(heat: 6.5, category: .frustrated, reason: "")
        let fresh = ScoreCombiner().combine(model: model, heuristic: calmReport, recentHeatedDrafts: 1)
        let rough = ScoreCombiner().combine(model: model, heuristic: calmReport, recentHeatedDrafts: 2)
        #expect(fresh.level == .warm)
        #expect(rough.level == .hot)
    }

    @Test func modelDeclinedIsAtLeastWarm() {
        let a = ScoreCombiner().combine(model: nil, modelDeclined: true, heuristic: calmReport, recentHeatedDrafts: 0)
        #expect(a.score == 6)
        #expect(a.level == .warm)
        #expect(a.rewrite == nil)
    }

    @Test func calmResultsDropRewriteAndCategory() {
        let a = ScoreCombiner().combine(model: ToneResult(heat: 2, category: .sarcastic, reason: "", rewrite: "x"),
                                        heuristic: calmReport, recentHeatedDrafts: 0)
        #expect(a.category == .calm)
        #expect(a.rewrite == nil)
    }

    @Test func modelSaysCalmButHeuristicsFlagPicksHeuristicCategory() {
        let a = ScoreCombiner().combine(model: ToneResult(heat: 1, category: .calm, reason: ""),
                                        heuristic: scorer.evaluate("Per my last message, as I already said, going forward"),
                                        recentHeatedDrafts: 0)
        #expect(a.level == .headsUp)
        #expect(a.category == .passiveAggressive)
    }

    @Test func trackerForgetsOldEvents() {
        var t = RecentHeatTracker(window: 60)
        let now = Date()
        t.record(at: now.addingTimeInterval(-120))
        t.record(at: now.addingTimeInterval(-30))
        #expect(t.count(now: now) == 1)
    }
}

@Suite("Ollama + privacy")
struct OllamaTests {
    @Test func onlyLoopbackHostsAllowed() {
        #expect(LoopbackGuard.isLoopback(URL(string: "http://127.0.0.1:11434")!))
        #expect(LoopbackGuard.isLoopback(URL(string: "http://localhost:11434")!))
        #expect(LoopbackGuard.isLoopback(URL(string: "http://[::1]:11434")!))
        #expect(!LoopbackGuard.isLoopback(URL(string: "http://192.168.1.5:11434")!))
        #expect(!LoopbackGuard.isLoopback(URL(string: "https://api.example.com")!))
        #expect(!LoopbackGuard.isLoopback(URL(string: "http://localhost.evil.com")!))
        #expect(throws: ToneAnalyzerError.self) { try OllamaToneAnalyzer(baseURL: URL(string: "http://10.0.0.2:11434")!) }
    }

    @Test func requestShape() throws {
        let analyzer = try OllamaToneAnalyzer(model: "qwen2.5:3b")
        let request = try analyzer.makeRequest(for: "hello")
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        #expect(body["model"] as? String == "qwen2.5:3b")
        #expect(body["stream"] as? Bool == false)
        #expect(body["format"] is [String: Any])
        let messages = body["messages"] as! [[String: String]]
        #expect(messages.last?["content"]?.contains("hello") == true)
    }

    @Test func envelopeDecoding() throws {
        let ok = #"{"model":"m","message":{"role":"assistant","content":"{\"heat\":3}"},"done":true}"#
        #expect(try OllamaToneAnalyzer.decodeEnvelope(Data(ok.utf8)) == #"{"heat":3}"#)
        let err = #"{"error":"model 'x' not found"}"#
        #expect(throws: ToneAnalyzerError.self) { try OllamaToneAnalyzer.decodeEnvelope(Data(err.utf8)) }
    }

    @Test func rotatorDoesNotRepeatBackToBack() {
        var r = PhraseRotator(["a", "b", "c"])
        var last = r.next()
        for _ in 0..<50 {
            let next = r.next()
            #expect(next != last)
            last = next
        }
    }
}
