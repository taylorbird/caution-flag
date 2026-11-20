import AppKit

/// A click-through veil over one screen, with a lit cut-out around the message box.
/// Sits just below the floating panels and never takes clicks or focus, so the
/// user can keep typing (or click anywhere) while it's up.
final class DimmingWindow: NSWindow {
    private let veil = VeilView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle, .stationary]
        animationBehavior = .none
        contentView = veil
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `hole` is in Cocoa screen coordinates; nil dims the whole screen.
    func show(around hole: CGRect?) {
        let screen = hole.flatMap { h in NSScreen.screens.first { $0.frame.intersects(h) } } ?? NSScreen.main
        guard let screen else { return }
        setFrame(screen.frame, display: false)
        veil.hole = hole.map { $0.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY).insetBy(dx: -8, dy: -8) }
        veil.needsDisplay = true
        guard !isVisible || alphaValue < 1 else { return }
        if !isVisible { alphaValue = 0 }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }
}

private final class VeilView: NSView {
    var hole: CGRect?

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        if let hole {
            path.append(NSBezierPath(roundedRect: hole, xRadius: 10, yRadius: 10))
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()
    }
}
