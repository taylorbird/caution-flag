import Foundation

/// Short, kind copy. Rotated so it never feels like a canned scold.
public enum Phrasings {
    /// The quiet heads-up chip. Short and low-key: a reread, not an alarm.
    public static let headsUp: [String] = [
        "Heads up: worth a reread",
        "Might be worth a second look",
        "Small flag on this one",
        "Could read a touch sharp",
    ]

    public static let warm: [String] = [
        "This is reading a little hot. Still want to send it?",
        "Might land sharper than you mean. Worth a second look?",
        "Quick pause? This one has some heat in it.",
        "Reads a bit tense. Send as-is, or soften it?",
        "Gentle flag: this could come across hot.",
    ]

    /// Headlines for the hot panel. One line each (about 24 characters at most), so
    /// the header never wraps. Racing-flavored to match the caution-flag look.
    public static let hot: [String] = [
        "Yellow flag. Ease off.",
        "Box, box, box.",
        "Lift and coast.",
        "Pit stop, maybe?",
        "Hold your line.",
        "Cool-down lap first?",
        "Easy on the throttle.",
        "Brakes before send.",
        "Spicy one, champ.",
        "Future you says hi.",
        "Sleep on it?",
        "Draft is running hot.",
    ]

    /// For a run of quick messages that adds up to more than any one of them.
    public static let burstWarm: [String] = [
        "A few quick ones in a row. Want to gather it into one?",
        "That's a fast run of messages. Pause and say it once?",
        "Quick-fire messages can stack up. One message instead?",
    ]

    /// Hot-panel headlines for a quick run of messages; one line each, like `hot`.
    public static let burstHot: [String] = [
        "Rapid fire. Pit stop?",
        "That's a quick run.",
        "Lots landing fast.",
        "Stacking up fast.",
    ]

    public static func reason(for category: ToneCategory) -> String {
        switch category {
        case .calm: "Reads calm and clear."
        case .frustrated: "There's some frustration coming through here."
        case .sarcastic: "Some of this could read as sarcastic."
        case .blaming: "This might land as blame, even if that's not the intent."
        case .passiveAggressive: "A few phrases here can read as passive-aggressive."
        case .venting: "Capitals, strong words, or lots of punctuation can read like shouting."
        }
    }
}

/// Hands out phrases in a shuffled order without repeating the previous one.
public struct PhraseRotator: Sendable {
    private let phrases: [String]
    private var queue: [String] = []
    private var last: String?

    public init(_ phrases: [String]) {
        precondition(!phrases.isEmpty)
        self.phrases = phrases
    }

    public mutating func next() -> String {
        if queue.isEmpty {
            queue = phrases.shuffled()
            if queue.count > 1, queue.first == last { queue.swapAt(0, 1) }
        }
        let phrase = queue.removeFirst()
        last = phrase
        return phrase
    }
}
