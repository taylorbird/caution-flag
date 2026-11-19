import AppKit
import SwiftUI

/// Drafts filed with "Not heated". Read-only review plus delete; the app never acts on these.
struct MisreadsView: View {
    @EnvironmentObject var store: MisreadStore
    @State private var confirmDeleteAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.reports.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.bubble").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("No reports yet").font(.headline)
                    Text("When a nudge misreads a message, tap \"Not heated\". It's kept here, private to this Mac, so the tuning can get better.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(store.reports) { report in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(report.appName).font(.caption.weight(.semibold))
                                Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) { store.delete(report) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                            }
                            Text(report.text).textSelection(.enabled).font(.body)
                            Text("\(report.level.capitalized) · \(String(format: "%.1f", report.score)) · \(report.category) · \(report.source)\(report.burst == true ? " · quick run" : "")")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(report.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                HStack {
                    Text("Stored only on this Mac.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.url]) }
                    Button("Delete all…") { confirmDeleteAll = true }
                }
                .padding(10)
            }
        }
        .frame(width: 560, height: 480)
        .confirmationDialog("Delete all reports?", isPresented: $confirmDeleteAll) {
            Button("Delete all", role: .destructive) { store.deleteAll() }
        }
    }
}
