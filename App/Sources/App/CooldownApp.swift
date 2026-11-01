import AppKit
import SwiftUI

@main
@MainActor
struct CooldownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(status: delegate.controller.statusItem, analyzers: delegate.controller.analyzers)
        } label: {
            MenuBarLabel(status: delegate.controller.statusItem)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var status: StatusItemController
    var body: some View { Image(nsImage: status.image) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created eagerly so the MenuBarExtra scene can bind to it before launch finishes.
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showSettings()
        return false
    }
}
