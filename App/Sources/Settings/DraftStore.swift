import Foundation

struct SavedDraft: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var appName: String
    var createdAt: Date
}

/// Drafts the user explicitly chose to save. This is the only place message text
/// is ever written to disk, and only on that explicit action.
@MainActor
final class DraftStore: ObservableObject {
    @Published private(set) var drafts: [SavedDraft] = []
    private let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Caution Flag", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        url = base.appendingPathComponent("drafts.json")
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([SavedDraft].self, from: data) {
            drafts = decoded
        }
    }

    func save(text: String, appName: String) {
        drafts.insert(SavedDraft(text: text, appName: appName, createdAt: Date()), at: 0)
        persist()
    }

    func delete(_ draft: SavedDraft) {
        drafts.removeAll { $0.id == draft.id }
        persist()
    }

    func deleteAll() {
        drafts.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
