import Foundation

/// Fixture messages for tests and the `cooldown-harness` CLI.
public struct SampleMessage: Sendable {
    public enum Expectation: Sendable {
        /// Calm: heuristics alone must not flag it.
        case calm
        /// Heated in an obvious way: heuristics alone should reach at least warm.
        case heatedObvious
        /// Heated in a subtle way: only a model is expected to catch it.
        case heatedSubtle
    }

    public let text: String
    public let expectation: Expectation

    public init(text: String, expectation: Expectation) {
        self.text = text
        self.expectation = expectation
    }
}

public enum SampleMessages {
    public static let calm: [SampleMessage] = [
        "Sounds good, thanks!",
        "Can you take a look at the PR when you get a chance?",
        "I'm running about 10 minutes late to standup.",
        "Thanks as always for jumping on this so fast.",
        "Never mind, figured it out!",
        "FYI the API docs are updated, link in the channel. LGTM on the QA plan.",
        "Great job on the launch yesterday, the numbers look strong.",
        "Could we move our 1:1 to Thursday? Something came up on my end.",
        "Hello there! Welcome to the team, let me know if you need anything.",
        "I think we might be misaligned on scope. Want to hop on a quick call to sort it out?",
        "No rush on this, whenever you have a minute this week.",
        "Ok, I'll handle the deploy and ping you when it's done.",
        // Paraphrased from Not heated reports (2026-11-20); the model has rated these 4–6.
        "oh, my mistake, I figured it was a caching issue. I read the log and thought those were changes you'd pushed.",
        "quick client question: I want a saved list of people I message a lot. It's just for me, nobody needs to join a group, more like a contact list.",
        "yep, the vendor exclusion is already in. Only open item is the question in the ticket title.",
    ].map { SampleMessage(text: $0, expectation: .calm) }

    public static let heatedObvious: [SampleMessage] = [
        "WHY IS THIS STILL BROKEN?? I ASKED FOR THIS LAST WEEK",
        "Per my last message, the deadline was Friday. Not sure why this is so hard.",
        "You always do this. Every single time we're close to launch you drop something on me!!!",
        "This is fucking ridiculous, who approved this garbage",
        "How many times do I have to explain this? Do your job.",
        "As I already said, the numbers are wrong. Once again, please fix them.",
        "This is your fault and frankly it's incompetent work.",
        "What were you thinking pushing that to prod without review?!?",
    ].map { SampleMessage(text: $0, expectation: .heatedObvious) }

    public static let heatedSubtle: [SampleMessage] = [
        "Interesting choice to ship that without telling anyone.",
        "I guess I'll just do it myself then, like usual.",
        "Not to be that person, but some of us actually read the spec.",
        "Must have missed the memo where deadlines became optional.",
        "Oh great, another meeting that could have been an email. Thanks a lot.",
        "Wow. Glad you finally decided to show up to the thread.",
    ].map { SampleMessage(text: $0, expectation: .heatedSubtle) }

    public static var all: [SampleMessage] { calm + heatedObvious + heatedSubtle }
}

/// A run of quick messages, scored together the way the app scores a burst.
/// Paraphrased: never paste real messages here (see constraints.md, Privacy).
public struct SampleBurst: Sendable {
    public let name: String
    public let messages: [String]
    /// True when the run, read together, should reach at least warm.
    public let heated: Bool

    public var combined: String { messages.joined(separator: "\n") }
}

public enum SampleBursts {
    public static let all: [SampleBurst] = [
        SampleBurst(name: "defensive rebuttal", messages: [
            "honestly hard to say since nobody has sent us any of these data issues",
            "which doesn't add up",
            "are they even filing these as data accuracy problems?",
            "because we have zero tickets 😞",
            "and the part about quality just isn't true",
        ], heated: true),
        SampleBurst(name: "excited", messages: [
            "omg yes",
            "that demo was so good",
            "can't believe it worked first try",
            "drinks friday? 🎉",
        ], heated: false),
        SampleBurst(name: "status updates", messages: [
            "pushed the fix",
            "deploying now",
            "should be live in 10 min",
            "I'll ping you when it's done",
        ], heated: false),
    ]
}
