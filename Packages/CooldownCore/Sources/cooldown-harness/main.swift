import CooldownCore
import Foundation

// Runs the sample calm/heated messages (or your own text) through the
// heuristics and, optionally, a live local model.
//
//   swift run cooldown-harness                     # heuristics only
//   swift run cooldown-harness --apple             # + Apple on-device model
//   swift run cooldown-harness --ollama [--model qwen2.5:3b]
//   swift run cooldown-harness --apple --text "per my last message..."
//   swift run cooldown-harness --apple --bursts    # quick-fire runs, scored together

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

let useApple = flag("--apple")
let useOllama = flag("--ollama")
let modelName = option("--model") ?? OllamaToneAnalyzer.defaultModel
let customText = option("--text")
let sensitivity = option("--sensitivity").flatMap(Double.init) ?? 3

var analyzer: ToneAnalyzer?
if useApple {
    if let a = AppleModelSupport.makeAnalyzer() { analyzer = a }
    else { print("Apple model unavailable: \(AppleModelSupport.unavailableReason ?? "unknown")"); exit(1) }
} else if useOllama {
    analyzer = try OllamaToneAnalyzer(model: modelName)
}

let scorer = HeuristicScorer()
let combiner = ScoreCombiner(sensitivity: sensitivity)
let burstMode = flag("--bursts")
let samples: [SampleMessage] = if let customText {
    [SampleMessage(text: customText, expectation: .heatedSubtle)]
} else if burstMode {
    // Each burst is scored as one combined text, as the app does.
    SampleBursts.all.map { SampleMessage(text: $0.combined, expectation: $0.heated ? .heatedSubtle : .calm) }
} else {
    SampleMessages.all
}

func label(_ e: SampleMessage.Expectation) -> String {
    switch e {
    case .calm: "calm  "
    case .heatedObvious: "heated"
    case .heatedSubtle: "subtle"
    }
}

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? String(s.prefix(n - 1)) + "…" : s + String(repeating: " ", count: n - s.count)
}

print("analyzer: \(analyzer?.displayName ?? "heuristics only")   sensitivity: \(sensitivity)\n")
var mismatches = 0
for sample in samples {
    let report = scorer.evaluate(sample.text)
    var model: ToneResult?
    var declined = false
    var elapsed = ""
    if let analyzer, !report.isObviouslyCalm || burstMode {
        let start = Date()
        do { model = try await withTimeout(30) { try await analyzer.analyze(sample.text) } }
        catch ToneAnalyzerError.declined { declined = true }
        catch { print("  ! \(error)") }
        elapsed = String(format: " %.1fs", Date().timeIntervalSince(start))
    }
    let a = combiner.combine(model: model, modelName: analyzer?.displayName, modelDeclined: declined,
                             heuristic: report, recentHeatedDrafts: 0)
    let level = switch a.level { case .calm: "🟢"; case .warm: "🟡"; case .hot: "🔴" }
    let expectedFlag = sample.expectation != .calm
    let ok = (a.level > .calm) == expectedFlag || (analyzer == nil && sample.expectation == .heatedSubtle)
    if !ok { mismatches += 1 }
    print("\(ok ? " " : "✗") \(label(sample.expectation)) \(level) \(String(format: "%4.1f", a.score)) h=\(String(format: "%.1f", report.score))\(model.map { String(format: " m=%.0f", $0.heat) } ?? "")\(declined ? " declined" : "")\(elapsed)  \(pad(sample.text, 60))")
    if let model, a.level > .calm {
        print("        \(a.category.displayName): \(model.reason)")
    }
    if let analyzer, a.level == .hot {
        let start = Date()
        let rewrite = try? await analyzer.suggestRewrite(sample.text)
        print(String(format: "        → (%.1fs) ", Date().timeIntervalSince(start)) + (rewrite ?? "(none)"))
    }
}
print("\n\(mismatches) mismatch(es) out of \(samples.count)")
