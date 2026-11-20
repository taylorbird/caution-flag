import Foundation

/// Live ("Caution Flag", com.tbird.cautionflag) or Dev ("Caution Flag Dev",
/// com.tbird.cautionflag.dev). scripts/build.sh picks the identity; the dev build has
/// no update feed and marks itself in the menu bar so it's never mistaken for live.
enum BuildFlavor {
    static let isDev = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true

    /// "0.1.4 (127)", for the menu.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
