import AppKit
import ApplicationServices
import CooldownCore
import os

/// A point-in-time read of the draft in the focused text field.
struct DraftSnapshot: Equatable {
    let text: String
    let bundleID: String
    let appName: String
    let pid: pid_t
    /// AX coordinates (top-left origin).
    let frame: CGRect?
    let element: AXUIElement
    /// Which conversation this composer belongs to: the focused window's title plus the
    /// composer element's identity. Memory only; logs carry a short hash, never the title.
    let conversation: String

    /// A short, non-reversible tag for logs, to check runs split per room.
    var conversationTag: String { Self.tag(conversation) }

    static func tag(_ s: String) -> String {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return String(format: "%04x", h & 0xffff)
    }

    static func == (lhs: DraftSnapshot, rhs: DraftSnapshot) -> Bool {
        lhs.text == rhs.text && lhs.pid == rhs.pid && lhs.frame == rhs.frame
    }
}

enum CaptureState: Equatable {
    case noPermission
    /// Carries the front app's bundle ID (not sensitive) for diagnostics.
    case notWatched(String?)
    case noTextField
    case secureField
    case captured(DraftSnapshot)
}

/// Polls the frontmost watched app's focused text field through the Accessibility API.
///
/// All AX calls run on a private serial queue with a short messaging timeout, so a
/// hung target app can never stall typing or our UI. Updates are delivered on main,
/// only when something changed. Text is held in memory only.
final class TextCaptureService: @unchecked Sendable {
    var onUpdate: (@MainActor (CaptureState) -> Void)?

    var watchedBundleIDs: Set<String> {
        get { lock.withLock { _watched } }
        set { lock.withLock { _watched = newValue } }
    }

    private let log = Logger(subsystem: "com.tbird.cautionflag", category: "capture")
    private let queue = DispatchQueue(label: "com.tbird.cautionflag.capture", qos: .userInitiated)
    private let lock = NSLock()
    private var _watched: Set<String> = []
    private var front: (pid: pid_t, bundleID: String, name: String)?
    private var timer: DispatchSourceTimer?
    private var lastState: CaptureState?
    private var manualAXEnabled = Set<pid_t>()
    private var cachedComposer: (pid: pid_t, element: AXUIElement)?
    private var lastDeepSearch = Date.distantPast
    private static let maxChars = 4000
    private static let textRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, "AXSearchField"]

    @MainActor
    func start() {
        updateFront(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateFront(app)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(250), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func updateFront(_ app: NSRunningApplication?) {
        lock.withLock {
            if let app, let id = app.bundleIdentifier {
                front = (app.processIdentifier, id, app.localizedName ?? id)
            } else {
                front = nil
            }
        }
    }

    // MARK: - Polling

    private func tick() {
        let state = readState()
        guard state != lastState else { return }
        lastState = state
        log.notice("capture state: \(Self.describe(state), privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onUpdate?(state) }
        }
    }

    /// State kind and length only, never the text.
    private static func describe(_ state: CaptureState) -> String {
        switch state {
        case .noPermission: "noPermission"
        case .notWatched(let id): "notWatched front=\(id ?? "unknown")"
        case .noTextField: "noTextField"
        case .secureField: "secureField"
        case .captured(let s): "captured len=\(s.text.count) frame=\(s.frame != nil)"
        }
    }

    private func readState() -> CaptureState {
        guard AXIsProcessTrusted() else { return .noPermission }
        let watched = lock.withLock { self._watched }
        guard let front = focusedApp() ?? lock.withLock({ self.front }) else {
            cachedComposer = nil
            return .notWatched(nil)
        }
        guard watched.contains(front.bundleID) else {
            cachedComposer = nil
            return .notWatched(front.bundleID)
        }

        let app = AXUIElementCreateApplication(front.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        enableElectronAccessibility(app, pid: front.pid)

        guard let field = findFocusedTextField(app: app, pid: front.pid) else { return .noTextField }
        if isSecure(field) { return .secureField }

        // Mention chips and the like can leak UI labels into the value; drop them.
        var text = CaptureCleanup.clean(AX.string(field, kAXValueAttribute) ?? "")
        if text.count > Self.maxChars { text = String(text.prefix(Self.maxChars)) }
        let window = AX.element(app, kAXFocusedWindowAttribute)
        let title = window.flatMap { AX.string($0, kAXTitleAttribute) } ?? ""
        return .captured(DraftSnapshot(
            text: text, bundleID: front.bundleID, appName: front.name, pid: front.pid,
            frame: AX.frame(field), element: field,
            conversation: "\(title)\u{1F}\(CFHash(field))"
        ))
    }

    /// Asks Accessibility which app has focus right now. Works from this background
    /// queue, unlike NSWorkspace's frontmost-app tracking, which needs the main run loop.
    private func focusedApp() -> (pid: pid_t, bundleID: String, name: String)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        guard let app = AX.element(system, kAXFocusedApplicationAttribute), let pid = AX.pid(app),
              let running = NSRunningApplication(processIdentifier: pid), let id = running.bundleIdentifier
        else { return nil }
        return (pid, id, running.localizedName ?? id)
    }

    /// Chromium/Electron apps (Slack) only build their AX tree when asked.
    private func enableElectronAccessibility(_ app: AXUIElement, pid: pid_t) {
        guard !manualAXEnabled.contains(pid) else { return }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        manualAXEnabled.insert(pid)
    }

    private func findFocusedTextField(app: AXUIElement, pid: pid_t) -> AXUIElement? {
        // 1. The app's focused element, or the system-wide one if that fails.
        var focused = AX.element(app, kAXFocusedUIElementAttribute)
        if focused == nil {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.25)
            if let candidate = AX.element(system, kAXFocusedUIElementAttribute), AX.pid(candidate) == pid {
                focused = candidate
            }
        }
        if let focused {
            if isSecure(focused) { return focused }
            if isTextInput(focused) { cachedComposer = (pid, focused); return focused }
            // Electron sometimes reports a wrapper group; look a few levels down.
            if let inner = focusedTextDescendant(of: focused, depth: 6) {
                cachedComposer = (pid, inner)
                return inner
            }
        }

        // 2. The composer we found last time, if it still has focus.
        if let cached = cachedComposer, cached.pid == pid, AX.bool(cached.element, kAXFocusedAttribute) == true {
            return cached.element
        }

        // 3. Last resort: walk the focused window for a focused text area. Rate-limited, it's slow.
        guard Date().timeIntervalSince(lastDeepSearch) > 2 else { return nil }
        lastDeepSearch = Date()
        guard let window = AX.element(app, kAXFocusedWindowAttribute) ?? AX.element(app, kAXMainWindowAttribute) else { return nil }
        if let found = breadthFirstFocusedText(in: window) {
            log.debug("composer found via deep search")
            cachedComposer = (pid, found)
            return found
        }
        return nil
    }

    private func isTextInput(_ element: AXUIElement) -> Bool {
        guard let role = AX.role(element) else { return false }
        if AX.subrole(element) == "AXSearchField" { return false }
        // Only editable text. A read-only text area (e.g. a Messages bubble that took
        // focus) carries other people's words; a Not heated report showed one being
        // rated as the draft. Composers in Slack, Echo and Messages report settable.
        if Self.textRoles.contains(role) {
            guard !Self.isReadOnly(element) else {
                // Role and pid only, never text: makes a composer that stops capturing visible.
                Self.readOnlyLog.debug("skipped read-only \(role, privacy: .public) pid=\(AX.pid(element) ?? 0)")
                return false
            }
            return true
        }
        // contenteditable regions sometimes show up as groups with a settable string value.
        return role == kAXGroupRole && AX.isValueSettable(element) && AX.string(element, kAXValueAttribute) != nil
    }

    private static let readOnlyLog = Logger(subsystem: "com.tbird.cautionflag", category: "capture")

    /// True only when the app answers that the value can't be set; unknown counts as editable.
    private static func isReadOnly(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && !settable.boolValue
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        AX.role(element) == "AXSecureTextField" || AX.subrole(element) == kAXSecureTextFieldSubrole
    }

    private func focusedTextDescendant(of element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth > 0 else { return nil }
        for child in AX.children(element) {
            if isTextInput(child), AX.bool(child, kAXFocusedAttribute) == true { return child }
            if let found = focusedTextDescendant(of: child, depth: depth - 1) { return found }
        }
        return nil
    }

    private func breadthFirstFocusedText(in root: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 2500 {
            let (node, depth) = queue.removeFirst()
            visited += 1
            if isTextInput(node), AX.bool(node, kAXFocusedAttribute) == true { return node }
            if depth < 45 {
                queue.append(contentsOf: AX.children(node).map { ($0, depth + 1) })
            }
        }
        return nil
    }

    // MARK: - Actions

    /// Empties the composer: AX first, then select-all + delete keystrokes for
    /// editors (like Slack's) that ignore direct value writes. Only runs on explicit user request.
    func clear(_ snapshot: DraftSnapshot) {
        queue.async {
            AXUIElementSetAttributeValue(snapshot.element, kAXValueAttribute as CFString, "" as CFString)
            let remaining = AX.string(snapshot.element, kAXValueAttribute) ?? ""
            guard !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Self.postKey(0x00, flags: .maskCommand, to: snapshot.pid) // ⌘A
            Self.postKey(0x33, flags: [], to: snapshot.pid)           // Delete
        }
    }

    private static func postKey(_ code: CGKeyCode, flags: CGEventFlags, to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            event.postToPid(pid)
        }
    }
}
