import AppKit
import CooldownCore
import SwiftUI

@MainActor
protocol StatusItemActions: AnyObject {
    func showSettings()
    func showOnboarding()
    func showDrafts()
    func toggleSnooze()
    func quit()
}

/// State behind the menu bar leaf (green / yellow / red while a draft is watched).
/// Rendered by the `MenuBarExtra` scene in `CooldownApp`.
@MainActor
final class StatusItemController: ObservableObject {
    private let settings: SettingsStore
    let analyzers: AnalyzerProvider
    weak var actions: StatusItemActions?

    @Published var level: HeatLevel?
    @Published var permissionMissing = false
    /// Bumped to re-evaluate time-based state (snooze expiry, quiet hours).
    @Published private var tick = 0

    init(settings: SettingsStore, analyzers: AnalyzerProvider, actions: StatusItemActions) {
        self.settings = settings
        self.analyzers = analyzers
        self.actions = actions
    }

    func refresh() { tick &+= 1 }

    var suppressionReason: String? { settings.suppressionReason }
    var isSnoozed: Bool { settings.isSnoozed }

    var headline: String {
        if permissionMissing { return "Needs Accessibility permission" }
        if let reason = settings.suppressionReason { return reason }
        let names = settings.watchedApps.map(\.name)
        return names.isEmpty ? "Not watching any apps" : "Watching \(ListFormatter.localizedString(byJoining: names))"
    }

    /// Template images follow the menu bar's own color; tinted ones must opt out
    /// of template rendering or the bar strips the color.
    var image: NSImage {
        let (symbol, color): (String, NSColor?)
        if permissionMissing {
            (symbol, color) = ("exclamationmark.triangle", nil)
        } else if settings.suppressionReason != nil {
            (symbol, color) = ("moon.zzz", nil)
        } else {
            switch level {
            case nil: (symbol, color) = ("leaf", nil)
            case .calm?: (symbol, color) = ("leaf.fill", .systemGreen)
            case .warm?: (symbol, color) = ("leaf.fill", .systemYellow)
            case .hot?: (symbol, color) = ("leaf.fill", .systemRed)
            }
        }
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "Cool-Down") ?? NSImage()
        guard let color else {
            base.isTemplate = true
            return base
        }
        let tinted = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) ?? base
        tinted.isTemplate = false
        return tinted
    }
}

struct StatusMenu: View {
    @ObservedObject var status: StatusItemController
    @ObservedObject var analyzers: AnalyzerProvider

    var body: some View {
        Text(status.headline)
        Text("Model: \(analyzers.statusText)")
        Divider()
        if status.permissionMissing {
            Button("Grant Accessibility Permission…") { status.actions?.showOnboarding() }
        }
        Button(status.isSnoozed ? "Resume Now" : "Snooze for 1 Hour") { status.actions?.toggleSnooze() }
        Button("Saved Drafts…") { status.actions?.showDrafts() }
        Button("Settings…") { status.actions?.showSettings() }
            .keyboardShortcut(",")
        Button("Setup Guide…") { status.actions?.showOnboarding() }
        Divider()
        Button("Quit Cool-Down") { status.actions?.quit() }
            .keyboardShortcut("q")
    }
}
