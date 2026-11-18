import Foundation

/// Short, kind copy. Rotated so it never feels like a canned scold.
public enum Phrasings {
    public static let warm: [String] = [
        "This is reading a little hot. Still want to send it?",
        "Might land sharper than you mean. Worth a second look?",
        "Quick pause? This one has some heat in it.",
        "Reads a bit tense. Send as-is, or soften it?",
        "Gentle flag: this could come across hot.",
    ]

    public static let hot: [String] = [
        "Let's take a breath before this one goes out.",
        "This one's carrying a lot. Want a minute with it?",
        "Strong feelings here, and that's okay. Pause first?",
        "You can still send it. Maybe just not yet?",
        "Worth sitting with this one for a moment.",
    ]

    /// For a run of quick messages that adds up to more than any one of them.
    public static let burstWarm: [String] = [
        "A few quick ones in a row. Want to gather it into one?",
        "That's a fast run of messages. Pause and say it once?",
        "Quick-fire messages can stack up. One message instead?",
    ]

    public static let burstHot: [String] = [
        "These quick messages are adding up. Breathe before the next one?",
        "A lot is landing fast here. Want a minute first?",
        "That run of messages carries some heat together. Pause?",
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
