import Foundation

public struct HeuristicSignal: Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case allCaps
        case shoutedWords
        case repeatedPunctuation
        case strongProfanity
        case mildProfanity
        case insult
        case absolutes
        case passiveAggressive
        case blaming
        case sarcasm
    }

    public let kind: Kind
    public let weight: Double
    public let matches: Int
}

public struct HeuristicReport: Equatable, Sendable {
    public let signals: [HeuristicSignal]
    /// True when the draft is short and has zero heat signals, so the model can be skipped.
    public let isObviouslyCalm: Bool

    /// Heuristic heat on the same 0–10 scale the model uses (capped).
    /// Different kinds of signal stacking up (e.g. blame + "?!?") earn a small bonus.
    public var score: Double {
        let sum = signals.reduce(0) { $0 + $1.weight }
        let stackBonus = signals.count >= 2 ? 0.5 : 0
        return min(HeuristicScorer.maxScore, sum + stackBonus)
    }

    public func has(_ kind: HeuristicSignal.Kind) -> Bool {
        signals.contains { $0.kind == kind }
    }

    public var suggestedCategory: ToneCategory {
        guard let top = signals.max(by: { $0.weight < $1.weight }) else { return .calm }
        switch top.kind {
        case .allCaps, .shoutedWords, .repeatedPunctuation, .strongProfanity: return .venting
        case .blaming: return .blaming
        case .passiveAggressive: return .passiveAggressive
        case .sarcasm: return .sarcastic
        case .mildProfanity, .insult, .absolutes: return .frustrated
        }
    }
}

/// Cheap, deterministic pre-checks. Runs on every analysis, never leaves the process.
public struct HeuristicScorer: Sendable {
    public static let maxScore = 8.0
    /// Drafts at or under this length with no signals skip the model entirely.
    public static let calmLengthLimit = 30

    public init() {}

    public func evaluate(_ raw: String) -> HeuristicReport {
        let text = Self.normalize(raw)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var signals: [HeuristicSignal] = []

        func add(_ kind: HeuristicSignal.Kind, matches: Int, first: Double, each: Double, cap: Double) {
            guard matches > 0 else { return }
            let weight = min(cap, first + each * Double(matches - 1))
            signals.append(HeuristicSignal(kind: kind, weight: weight, matches: matches))
        }

        // Shouting.
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let uppers = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
        if letters.count >= 10, Double(uppers.count) / Double(letters.count) >= 0.7 {
            signals.append(HeuristicSignal(kind: .allCaps, weight: 3, matches: 1))
        } else {
            let shouted = Self.words(in: text).filter {
                $0.count >= 3 && $0 == $0.uppercased() && $0 != $0.lowercased() && !Self.acronyms.contains($0)
            }
            if shouted.count >= 2 {
                signals.append(HeuristicSignal(kind: .shoutedWords, weight: 1.5, matches: shouted.count))
            } else if let only = shouted.first, only.count >= 5 {
                signals.append(HeuristicSignal(kind: .shoutedWords, weight: 0.75, matches: 1))
            }
        }

        add(.repeatedPunctuation, matches: Self.count(Self.repeatedPunctuation, in: text), first: 1, each: 0.5, cap: 2)
        add(.strongProfanity, matches: Self.count(Self.strongProfanity, in: text), first: 2.5, each: 0.5, cap: 3.5)
        add(.mildProfanity, matches: Self.count(Self.mildProfanity, in: text), first: 1, each: 0.5, cap: 1.5)
        add(.insult, matches: Self.count(Self.insults, in: text), first: 2.5, each: 0.5, cap: 3.5)
        add(.absolutes, matches: Self.count(Self.absolutes, in: text), first: 0.75, each: 0.75, cap: 1.5)
        add(.passiveAggressive, matches: Self.count(Self.passiveAggressive, in: text), first: 2.5, each: 1.5, cap: 4)
        add(.blaming, matches: Self.count(Self.blaming, in: text), first: 2.5, each: 1.5, cap: 4)
        add(.sarcasm, matches: Self.count(Self.sarcasm, in: text), first: 1.5, each: 1, cap: 2.5)

        let calm = signals.isEmpty && trimmed.count <= Self.calmLengthLimit
        return HeuristicReport(signals: signals, isObviouslyCalm: calm)
    }

    // MARK: - Patterns

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    static func words(in s: String) -> [String] {
        s.split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    private static func regex(_ patterns: [String]) -> NSRegularExpression {
        let joined = patterns.map { "(?:\($0))" }.joined(separator: "|")
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: joined, options: [.caseInsensitive])
    }

    private static func count(_ re: NSRegularExpression, in s: String) -> Int {
        re.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    static let repeatedPunctuation = try! NSRegularExpression(pattern: "[!?]{2,}")

    static let strongProfanity = regex([
        #"\bfuck\w*"#, #"\bf\*+k\w*"#, #"\bshit\w*"#, #"\bbullshit\b"#, #"\bwtf\b"#,
        #"\basshole\w*"#, #"\bgoddamn\w*"#, #"\bmotherf\w*"#, #"\bpiss(?:ed)? off\b"#,
    ])

    static let mildProfanity = regex([
        #"\bdamn\w*"#, #"\bcrap\w*"#, #"\bpissed\b(?! off)"#, #"\bhell\b"#, #"\bjesus christ\b"#,
    ])

    static let insults = regex([
        #"\bidiot\w*"#, #"\bstupid\w*"#, #"\bincompetent\b"#, #"\bincompetence\b"#, #"\bmoron\w*"#,
        #"\buseless\b"#, #"\bpathetic\b"#, #"\bridiculous\b"#, #"\bclown\w*"#, #"\blazy\b"#,
        #"\bdumb\w*"#, #"\bamateur\w*"#, #"\b(?:is|was) a joke\b"#,
    ])

    static let absolutes = regex([
        #"(?<!as )\balways\b"#, #"\bnever\b(?! mind)"#, #"\bevery (?:single )?time\b"#,
        #"\bnobody\b"#, #"\bno one\b"#, #"\bconstantly\b"#,
    ])

    static let passiveAggressive = regex([
        #"\bper my (?:last|previous)\b"#, #"\bas per my\b"#,
        #"\bas i (?:already |previously |have )?(?:said|mentioned|stated|explained|noted)\b"#,
        #"\bas (?:previously|already) (?:stated|mentioned|discussed|noted)\b"#,
        #"\bjust to be clear\b"#, #"\bgoing forward\b"#, #"\b(?:friendly|gentle|quick) reminder\b"#,
        #"\bwith all due respect\b"#, #"\bnot sure (?:why|how|what) (?:this|that|it)\b"#,
        #"\bi'?m not sure what'?s unclear\b"#, #"\bto reiterate\b"#, #"\bonce again\b"#,
        #"\bfor the (?:\w+ )?(?:second|third|fourth|fifth|hundredth|nth|last) time\b"#,
        #"\bplease advise\b"#, #"\bre-?attach(?:ing|ed)\b"#, #"\bthanks in advance for your cooperation\b"#,
    ])

    static let blaming = regex([
        #"\byour fault\b"#, #"\byou (?:always|never|constantly|keep)\b"#,
        #"\bwhy (?:didn'?t|did|would|can'?t|couldn'?t|won'?t|wouldn'?t|haven'?t|aren'?t) you\b"#,
        #"\bhow many times\b"#, #"\byou people\b"#, #"\bbecause of you\b"#,
        #"\byou were supposed to\b"#, #"\byou dropped the ball\b"#,
        #"\byou (?:screwed|messed|fucked) (?:up|this up|it up)\b"#, #"\b(?:this|that) is on you\b"#,
        #"\bwhat (?:were|was) you thinking\b"#, #"\bdo your job\b"#,
    ])

    static let sarcasm = regex([
        #"\bgreat job\b"#, #"\bthanks a lot\b"#, #"\boh,? (?:great|wonderful|perfect|fantastic|good|cool)\b"#,
        #"\bmust be nice\b"#, #"(?:^|\s)/s\b"#, #"\bwow\.(?:\s|$)"#, #"\bnice of you to\b"#,
        #"\bglad you (?:could|finally)\b"#, #"\bclearly you\b"#, #"\bthanks for nothing\b"#,
        #"\bwhat a surprise\b"#, #"\bshocker\b"#,
    ])

    static let acronyms: Set<String> = [
        "ASAP", "FYI", "API", "ETA", "EOD", "OOO", "CEO", "CTO", "CFO", "COO", "URL", "PDF", "SQL", "AWS",
        "JSON", "HTTP", "HTTPS", "IMO", "IMHO", "TBD", "TBH", "LGTM", "ICYMI", "KPI", "OKR", "SLA", "EST",
        "PST", "PDT", "EDT", "UTC", "USA", "NYC", "FAQ", "ROI", "MVP", "SDK", "IOS", "GCP", "DNS", "SSO",
        "LOL", "IIRC", "AFAIK", "WFH", "PTO", "SEO", "CSS", "HTML", "NPM", "CLI", "NDA", "SOW", "RFC", "WIP",
        "CRM", "SKU", "B2B", "DTC", "QBR", "OKRS", "KPIS", "PRS", "APIS", "ETL", "GPU", "CPU", "RAM", "SSD",
        "YAML", "XML", "CSV", "AI", "ML", "LLM", "GPT", "AWS", "RSVP", "TLDR", "ATM", "BTW", "OMG", "HQ",
    ]
}
