import AppKit
import SwiftUI

/// A borderless, non-activating panel: it floats over Slack and takes clicks
/// without stealing focus from the composer.
final class FloatingPanel<Content: View>: NSPanel {
    private let hosting: NSHostingController<WholePointSized<Content>>

    init(rootView: Content) {
        hosting = NSHostingController(rootView: WholePointSized(content: rootView))
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
        get { hosting.rootView.content }
        set { hosting.rootView = WholePointSized(content: newValue) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    enum Spot: String { case above, below, trailing, leading, corner }

    /// Places the window next to the message box (`anchor`, Cocoa coordinates) without
    /// ever covering it: above if there's room, else below, else beside it. An anchor
    /// that can't be a message box (missing, or most of the screen tall, as some
    /// Electron apps report) gets the screen's top-trailing corner instead.
    @discardableResult
    func place(near anchor: CGRect?) -> Spot {
        hosting.view.layoutSubtreeIfNeeded()
        // fittingSize, not sizeThatFits(in: huge): flexible spacers would stretch to fill
        // a huge proposal and every spot would look too small.
        let size = hosting.view.fittingSize
        let w = size.width.rounded(.up), h = size.height.rounded(.up)
        setContentSize(CGSize(width: w, height: h))

        let probe = anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.intersects(probe.insetBy(dx: -1, dy: -1)) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let corner = CGPoint(x: visible.maxX - w - 16, y: visible.maxY - h - 16)

        guard let a = anchor, a.height <= visible.height * 0.45 else {
            setFrameOrigin(corner)
            return .corner
        }
        let gap: CGFloat = 10
        let candidates: [(Spot, CGPoint)] = [
            (.above, CGPoint(x: a.minX + 12, y: a.maxY + gap)),
            (.below, CGPoint(x: a.minX + 12, y: a.minY - h - gap)),
            (.trailing, CGPoint(x: a.maxX + gap, y: a.minY)),
            (.leading, CGPoint(x: a.minX - w - gap, y: a.minY)),
        ]
        let box = a.insetBy(dx: -4, dy: -4)
        for (spot, origin) in candidates {
            // Only slide along the edge we're on; a spot that needs moving into the box fails.
            let x = min(max(origin.x, visible.minX + 8), visible.maxX - w - 8)
            let y = min(max(origin.y, visible.minY + 8), visible.maxY - h - 8)
            let frame = CGRect(x: x, y: y, width: w, height: h)
            if visible.contains(frame), !frame.intersects(box) {
                setFrameOrigin(frame.origin)
                return spot
            }
        }
        setFrameOrigin(corner)
        return .corner
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

/// Rounds the content's size up to whole points.
///
/// With `.preferredContentSize`, SwiftUI resizes the window to the content's size, but
/// windows snap to whole points: a 52.5 pt pill becomes 53 pt, SwiftUI asks for 52.5
/// again, and the resize/layout cycle can recurse until the stack overflows (the
/// 0.1.2 crash when the warm pill first appeared). Whole-point content ends the cycle.
struct WholePointSized<Content: View>: View {
    var content: Content

    var body: some View {
        WholePointLayout { content }
    }
}

private struct WholePointLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                              proposal: ProposedViewSize(bounds.size))
    }
}
