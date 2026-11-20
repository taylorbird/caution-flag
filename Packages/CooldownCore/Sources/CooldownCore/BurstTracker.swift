import Foundation

/// Notices rapid-fire sending: several short messages sent one after another.
/// Each message can read calm on its own while the run of them reads defensive,
/// so a burst's recent messages are scored together with the next draft.
///
/// Holds recently sent text in memory only, for at most `window` seconds.
/// It is never written to disk or logged.
public struct BurstTracker: Sendable {
    /// The oldest send that still counts toward a burst.
    public var window: TimeInterval
    /// A pause longer than this ends the burst.
    public var maxGap: TimeInterval
    /// A long message isn't rapid-fire; it ends the burst.
    public var maxLength: Int
    /// Sends needed before the next draft is scored as part of a burst.
    public var minPriorSends: Int
    /// The most recent sends kept for context.
    public var maxKept: Int

    private var sends: [(date: Date, text: String)] = []

    public init(window: TimeInterval = 180, maxGap: TimeInterval = 60, maxLength: Int = 200,
                minPriorSends: Int = 2, maxKept: Int = 6) {
        self.window = window
        self.maxGap = maxGap
        self.maxLength = maxLength
        self.minPriorSends = minPriorSends
        self.maxKept = maxKept
    }

    /// The "speed check" slider: 1 (relaxed) … 5 (watchful). Higher counts slower,
    /// longer runs. 5 matches the original 0.1.2 behavior; 3 is the default.
    public struct Tuning: Equatable, Sendable {
        public let maxGap: TimeInterval
        public let maxLength: Int
        public let minPriorSends: Int
    }

    public static func tuning(level: Double) -> Tuning {
        switch Int(min(5, max(1, level)).rounded()) {
        case 1: Tuning(maxGap: 10, maxLength: 60, minPriorSends: 4)
        case 2: Tuning(maxGap: 15, maxLength: 70, minPriorSends: 3)
        case 4: Tuning(maxGap: 35, maxLength: 140, minPriorSends: 2)
        case 5: Tuning(maxGap: 60, maxLength: 200, minPriorSends: 2)
        default: Tuning(maxGap: 20, maxLength: 80, minPriorSends: 3)
        }
    }

    public init(level: Double) {
        self.init()
        configure(level: level)
    }

    /// Applies the slider without forgetting the current run.
    public mutating func configure(level: Double) {
        let t = Self.tuning(level: level)
        maxGap = t.maxGap
        maxLength = t.maxLength
        minPriorSends = t.minPriorSends
    }

    public mutating func recordSend(_ text: String, at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else {
            sends.removeAll()
            return
        }
        prune(now: date)
        sends.append((date, trimmed))
        if sends.count > maxKept { sends.removeFirst(sends.count - maxKept) }
    }

    /// The burst's earlier messages, oldest first, or nil when there's no burst.
    public mutating func context(now: Date = Date()) -> [String]? {
        prune(now: now)
        return sends.count >= minPriorSends ? sends.map(\.text) : nil
    }

    public var sendCount: Int { sends.count }

    public mutating func reset() {
        sends.removeAll()
    }

    private mutating func prune(now: Date) {
        if let last = sends.last, now.timeIntervalSince(last.date) > maxGap {
            sends.removeAll()
            return
        }
        sends.removeAll { now.timeIntervalSince($0.date) > window }
    }

    /// The text the model sees: the burst's messages, then the draft, one per line.
    public static func combined(_ context: [String], draft: String) -> String {
        (context + [draft.trimmingCharacters(in: .whitespacesAndNewlines)]).joined(separator: "\n")
    }
}
