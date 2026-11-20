import AppKit
import CooldownCore
import SwiftUI

@MainActor
protocol StatusItemActions: AnyObject {
    func showSettings()
    func showOnboarding()
    func checkForUpdates()
    func showDrafts()
    func showMisreads()
    func toggleSnooze()
    func quit()
}

/// State behind the menu bar pennant (green / yellow / red while watching).
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
        if permissionMissing {
            let warning = NSImage(systemSymbolName: "exclamationmark.triangle",
                                  accessibilityDescription: "Caution Flag needs permission") ?? NSImage()
            warning.isTemplate = true
            return warning
        }
        if settings.suppressionReason != nil || settings.watchedApps.isEmpty {
            // Off: a plain silhouette in the menu bar's own color.
            return Self.pennant(color: nil)
        }
        // On: racing flag colors, so "watching" reads at a glance.
        switch level {
        case nil, .calm?: return Self.pennant(color: .systemGreen)
        case .headsUp?: return Self.pennant(color: .systemBlue)
        case .warm?: return Self.pennant(color: .systemYellow)
        case .hot?: return Self.pennant(color: .systemRed)
        }
    }

    /// The app icon's pennant, drawn at menu bar size (18 pt grid). Same
    /// geometry as assets/icon/caution-flag.svg, scaled and centered.
    static func pennant(color: NSColor?) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            (color ?? .black).setFill()
            NSBezierPath(roundedRect: NSRect(x: 4, y: 1.5, width: 1.8, height: 15), xRadius: 0.9, yRadius: 0.9).fill()
            let flag = NSBezierPath()
            flag.move(to: NSPoint(x: 5.8, y: 2.6))
            flag.line(to: NSPoint(x: 14.6, y: 6.6))
            flag.line(to: NSPoint(x: 5.8, y: 10.6))
            flag.close()
            flag.lineJoinStyle = .round
            flag.lineWidth = 1.2
            (color ?? .black).setStroke()
            flag.fill()
            flag.stroke()
            if BuildFlavor.isDev {
                // Dev build: an orange dot in the corner, so it's never mistaken for live.
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: NSRect(x: 11.5, y: 11.5, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = color == nil && !BuildFlavor.isDev
        image.accessibilityDescription = "Caution Flag"
        return image
    }
}

struct StatusMenu: View {
    @ObservedObject var status: StatusItemController
    @ObservedObject var analyzers: AnalyzerProvider
    @ObservedObject var login: LaunchAtLogin

    var body: some View {
        Text(status.headline)
        Text("Model: \(analyzers.statusText)")
        if BuildFlavor.isDev {
            Text("Dev build \(BuildFlavor.versionLine) · no auto-updates")
        }
        Divider()
        if status.permissionMissing {
            Button("Grant Accessibility Permission…") { status.actions?.showOnboarding() }
        }
        Button(status.isSnoozed ? "Resume Now" : "Snooze for 1 Hour") { status.actions?.toggleSnooze() }
        Button("Saved Drafts…") { status.actions?.showDrafts() }
        Button("Not Heated Reports…") { status.actions?.showMisreads() }
        Button("Settings…") { status.actions?.showSettings() }
            .keyboardShortcut(",")
        Button("Setup Guide…") { status.actions?.showOnboarding() }
        if !BuildFlavor.isDev {
            Button("Check for Updates…") { status.actions?.checkForUpdates() }
        }
        Divider()
        Toggle("Open at Login", isOn: Binding(
            get: { login.isEnabled || login.needsApproval },
            set: { login.setEnabled($0) }
        ))
        if login.needsApproval {
            Button("Allow in Login Items…") { login.openLoginItemsSettings() }
        }
        Divider()
        Button(BuildFlavor.isDev ? "Quit Caution Flag Dev" : "Quit Caution Flag") { status.actions?.quit() }
            .keyboardShortcut("q")
    }
}
