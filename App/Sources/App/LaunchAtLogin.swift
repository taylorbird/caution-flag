import Foundation
import os
import ServiceManagement

/// Open-at-login via the app's own login item. macOS owns this state (the user
/// can also flip it in System Settings > General > Login Items), so it is read
/// live from SMAppService and never mirrored into UserDefaults.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?

    private let log = Logger(subsystem: "com.tbird.cooldown", category: "login")
    private var service: SMAppService { .mainApp }

    init() { refresh() }

    var isEnabled: Bool { status == .enabled }
    /// Registered, but macOS wants the user to allow it in System Settings.
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = service.status }

    func setEnabled(_ on: Bool) {
        do {
            if on { try service.register() } else { try service.unregister() }
            lastError = nil
            log.notice("open at login \(on ? "registered" : "unregistered", privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            log.error("open at login \(on ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
