import AppKit
import CooldownCore
import SwiftUI

/// Owns every long-lived service and wires them together.
@MainActor
final class AppController {
    let settings = SettingsStore()
    let drafts = DraftStore()
    let misreads = MisreadStore()
    let login = LaunchAtLogin()
    lazy var analyzers = AnalyzerProvider(settings: settings)
    let capture = TextCaptureService()
    let windows = WindowManager()
    let updates = UpdateController(enabled: UserDefaults.standard.string(forKey: "demo") == nil)
    lazy var interventions = InterventionController(settings: settings)
    lazy var statusItem = StatusItemController(settings: settings, analyzers: analyzers, actions: self)
    lazy var coordinator = DraftCoordinator(
        settings: settings, analyzers: analyzers, interventions: interventions,
        status: statusItem, capture: capture, drafts: drafts, misreads: misreads
    )

    private var refreshTimer: Timer?

    func start() {
        capture.watchedBundleIDs = settings.watchedBundleIDs
        settings.onWatchedAppsChange = { [weak self] ids in self?.capture.watchedBundleIDs = ids }
        capture.onUpdate = { [weak self] state in self?.coordinator.handle(state) }
        _ = coordinator // wires InterventionController.actions
        if UserDefaults.standard.string(forKey: "demo") == nil {
            capture.start()
        }

        // Snooze expiry and quiet hours change state without any typing.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.refreshSuppression() }
        }

        if let demo = UserDefaults.standard.string(forKey: "demo") {
            runDemo(demo)
        } else if !settings.onboardingCompleted || !AccessibilityPermission.isTrusted {
            showOnboarding()
        }
    }

    /// Visual smoke test without Slack: `Cooldown.app/Contents/MacOS/Cooldown -demo hot`.
    private func runDemo(_ which: String) {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let axAnchor = CGRect(x: screen.midX - 300, y: 300, width: 600, height: 40)
        let assessment = ToneAssessment(
            score: which == "warm" ? 5 : 8.5, category: .blaming,
            reason: "This might land as blame, even if you mostly want it fixed.",
            rewrite: which == "warm" ? nil : "Hey, I noticed this went out without review. Could we walk through what happened and tighten the process?",
            source: .model("demo")
        )
        switch which {
        case "warm": interventions.showPill(for: assessment, anchor: axAnchor)
        case "breathing": interventions.showBreathing(anchor: axAnchor)
        case "onboarding": showOnboarding()
        case "settings": showSettings()
        default:
            interventions.showPanel(for: assessment, anchor: axAnchor,
                                    notes: settings.personalNotes.isEmpty ? "Remember: send it tomorrow morning instead." : settings.personalNotes)
        }
    }
}

extension AppController: StatusItemActions {
    func checkForUpdates() {
        updates.checkForUpdates()
    }

    func showSettings() {
        windows.show(id: "settings", title: "Caution Flag Settings", size: CGSize(width: 560, height: 520)) {
            SettingsView()
                .environmentObject(self.settings)
                .environmentObject(self.analyzers)
                .environmentObject(self.login)
        }
    }

    func showOnboarding() {
        windows.show(id: "onboarding", title: "Welcome to Caution Flag", size: CGSize(width: 560, height: 760)) {
            OnboardingView(onDone: { [weak self] in
                self?.settings.onboardingCompleted = true
                self?.windows.close(id: "onboarding")
            })
            .environmentObject(self.settings)
            .environmentObject(self.analyzers)
        }
    }

    func showDrafts() {
        windows.show(id: "drafts", title: "Saved Drafts", size: CGSize(width: 520, height: 440)) {
            DraftsView().environmentObject(self.drafts)
        }
    }

    func showMisreads() {
        windows.show(id: "misreads", title: "Not Heated", size: CGSize(width: 560, height: 480)) {
            MisreadsView().environmentObject(self.misreads)
        }
    }

    func toggleSnooze() {
        if settings.isSnoozed {
            settings.snoozeUntil = nil
        } else {
            settings.snoozeUntil = Date().addingTimeInterval(3600)
        }
        coordinator.refreshSuppression()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

/// Plain AppKit windows hosting SwiftUI, since menu bar apps can't rely on `WindowGroup`.
@MainActor
final class WindowManager {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: CGSize, @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            bringForward(existing)
            return
        }
        let hosting = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        bringForward(window)
    }

    /// Accessory (menu bar) apps aren't activated by a plain launch, so a new window
    /// can land behind everything. Activate, then force it up regardless.
    private func bringForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close(id: String) {
        windows[id]?.close()
    }
}
