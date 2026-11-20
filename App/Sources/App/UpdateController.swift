import Foundation
import Sparkle

/// In-app updates via Sparkle. Checks the appcast on the public tap repo once a day,
/// downloads signed updates in the background and installs them on the next relaunch.
/// Demo runs (`-demo …`) never start the updater.
@MainActor
final class UpdateController {
    private let controller: SPUStandardUpdaterController

    init(enabled: Bool) {
        controller = SPUStandardUpdaterController(startingUpdater: enabled, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
