import CooldownCore
import Foundation

/// A draft the owner marked "Not heated": the app flagged it, but it didn't need a reaction.
/// Collected for review each dev cycle; the app never changes its behavior because of these.
struct MisreadReport: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var appName: String
    var createdAt: Date
    /// Combined 0–10 score and the level it produced (calm / warm / hot).
    var score: Double
    var level: String
    var category: String
    var reason: String
    /// "heuristics", "model:<name>", or "declined:<name>".
    var source: String
    /// The Sensitivity setting at the time, since it shifts the combined score.
    var sensitivity: Double
    /// True when the text is a quick run of messages scored together (one per line).
    var burst: Bool? = nil
}

/// Reports the owner explicitly filed with "Not heated". Like `DraftStore`, text is
/// written to disk only on that explicit action, mode 600, and never leaves this Mac.
@MainActor
final class MisreadStore: ObservableObject {
    @Published private(set) var reports: [MisreadReport] = []
    let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Caution Flag", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        url = base.appendingPathComponent("misreads.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let decoded = try? decoder.decode([MisreadReport].self, from: data) {
            reports = decoded
        }
    }

    func record(text: String, appName: String, assessment: ToneAssessment, sensitivity: Double, burst: Bool) {
        let source: String = switch assessment.source {
        case .heuristicsOnly: "heuristics"
        case .model(let name): "model:\(name)"
        case .modelDeclined(let name): "declined:\(name)"
        }
        let level: String = switch assessment.level {
        case .calm: "calm"
        case .warm: "warm"
        case .hot: "hot"
        }
        reports.insert(MisreadReport(
            text: text, appName: appName, createdAt: Date(),
            score: assessment.score, level: level, category: assessment.category.rawValue,
            reason: assessment.reason, source: source, sensitivity: sensitivity, burst: burst
        ), at: 0)
        persist()
    }

    func delete(_ report: MisreadReport) {
        reports.removeAll { $0.id == report.id }
        persist()
    }

    func deleteAll() {
        reports.removeAll()
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(reports) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
