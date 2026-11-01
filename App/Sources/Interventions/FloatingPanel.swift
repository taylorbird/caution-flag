import AppKit
import SwiftUI

/// A borderless, non-activating panel: it floats over Slack and takes clicks
/// without stealing focus from the composer.
final class FloatingPanel<Content: View>: NSPanel {
    private let hosting: NSHostingController<Content>

    init(rootView: Content) {
        hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        contentViewController = hosting
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
    }

    var rootView: Content {
        get { hosting.rootView }
        set { hosting.rootView = newValue }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Places the panel just above `anchor` (Cocoa coordinates), or near the mouse.
    func position(above anchor: CGRect?, alignment: HorizontalAlignment = .leading) {
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        setContentSize(size)

        let target = anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.intersects(target.insetBy(dx: -1, dy: -1)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        var x: CGFloat
        switch alignment {
        case .trailing: x = target.maxX - size.width - 12
        case .center: x = target.midX - size.width / 2
        default: x = target.minX + 12
        }
        var y = target.maxY + 10
        if y + size.height > visible.maxY { y = target.minY - size.height - 10 }

        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    func centerOnScreen(near anchor: CGRect?) {
        hosting.view.layoutSubtreeIfNeeded()
        setContentSize(hosting.view.fittingSize)
        let screen = anchor.flatMap { a in NSScreen.screens.first { $0.frame.intersects(a) } } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { center(); return }
        setFrameOrigin(CGPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2 + 60))
    }

    func fadeIn() {
        guard !isVisible else { return }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
    }

    func fadeOut() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }
}
