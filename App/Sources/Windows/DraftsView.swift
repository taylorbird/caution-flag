import AppKit
import SwiftUI

struct DraftsView: View {
    @EnvironmentObject var store: DraftStore
    @State private var confirmDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.drafts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("No saved drafts").font(.headline)
                    Text("When you choose \"Save draft for later\", it lands here, private to this Mac.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(store.drafts) { draft in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(draft.appName).font(.caption.weight(.semibold))
                                Text(draft.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(draft.text, forType: .string)
                                }
                                .controlSize(.small)
                                Button(role: .destructive) { store.delete(draft) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                            }
                            Text(draft.text).textSelection(.enabled).font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
                HStack {
                    Text("Stored only on this Mac.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete all…") { confirmDeleteAll = true }
                }
                .padding(10)
            }
        }
        .frame(width: 520, height: 440)
        .confirmationDialog("Delete all saved drafts?", isPresented: $confirmDeleteAll) {
            Button("Delete all", role: .destructive) { store.deleteAll() }
        }
    }
}
