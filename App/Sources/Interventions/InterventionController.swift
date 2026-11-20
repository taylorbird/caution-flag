import AppKit
import CooldownCore
import os
import SwiftUI

@MainActor
protocol InterventionActions: AnyObject {
    func dismissForThisDraft()
    func expandPill()
    func takeFive()
    /// Returns true if something was saved.
    func saveDraft() -> Bool
    func clearComposer()
    /// "Not heated": file the current draft as a misread. Returns true if something was saved.
    func markNotHeated() -> Bool
    /// "Why?": ask the model, on demand, what in the wording drove the rating.
    func explain()
    /// "Just this one": stop reading the quick run with this draft.
    func justThisOne()
}

/// The on-demand "Why?" answer as the UI sees it. Draft-derived, so memory only.
enum WhyState: Equatable {
    case idle, loading
    case ready(ToneExplanation)
    case failed(String)
}

/// Shared state for the small nudge (heads-up chip or warm pill).
@MainActor
final class NudgeModel: ObservableObject {
    enum Style { case headsUp, warm }
    @Published var style = Style.headsUp
    @Published var message = ""
    @Published var why = WhyState.idle
    @Published var notedMisread = false
    /// Earlier messages being read with the draft, when the flag is the run's.
    @Published var runCount: Int?
}

/// Shared state for the larger panel so SwiftUI can update in place.
@MainActor
final class PanelModel: ObservableObject {
    enum SaveState { case idle, saved, cleared }
    @Published var headline = ""
    @Published var assessment: ToneAssessment?
    @Published var notes = ""
    @Published var saveState = SaveState.idle
    @Published var copied = false
    @Published var rewriteLoading = false
    @Published var notedMisread = false
    @Published var why = WhyState.idle
    @Published var runCount: Int?
}

/// Owns the floating UI: the heads-up chip and warm pill (one small window), the larger
/// "hot" panel, and the breathing timer.
@MainActor
final class InterventionController {
    weak var actions: InterventionActions?
    private let settings: SettingsStore

    private var headsUpPhrases = PhraseRotator(Phrasings.headsUp)
    private var warmPhrases = PhraseRotator(Phrasings.warm)
    private var hotPhrases = PhraseRotator(Phrasings.hot)
    private var burstWarmPhrases = PhraseRotator(Phrasings.burstWarm)
    private var burstHotPhrases = PhraseRotator(Phrasings.burstHot)

    private let nudgeModel = NudgeModel()
    private var nudge: FloatingPanel<NudgeView>?
    private let log = Logger(subsystem: "com.tbird.cautionflag", category: "ui")
    private var nudgeHideTask: Task<Void, Never>?

    private let panelModel = PanelModel()
    private var panel: FloatingPanel<HotPanelView>?
    private lazy var dimmer = DimmingWindow()
    private let motion = MotionClock()

    private var breathing: FloatingPanel<BreathingView>?
    private var anchor: CGRect?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isShowingAnything: Bool {
        (nudge?.isVisible ?? false) || (panel?.isVisible ?? false)
    }

    /// `axFrame` is in AX coordinates. When the message box moves or grows (a longer
    /// draft) under a visible nudge or panel, the window moves out of its way.
    func updateAnchor(_ axFrame: CGRect?) {
        let new = axFrame.map(AX.cocoaRect(fromAX:))
        let changed = new != anchor
        anchor = new
        if changed { keepClearOfMessageBox() }
    }

    /// Moves a visible nudge or near-message panel only if it now covers the message box,
    /// so nothing jumps around otherwise.
    private func keepClearOfMessageBox() {
        guard let anchor else { return }
        let box = anchor.insetBy(dx: -4, dy: -4)
        // Also re-place a window that grew past the screen edge (it grows upward).
        func offScreen(_ frame: CGRect) -> Bool {
            let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
            return !(screen?.visibleFrame.contains(frame) ?? true)
        }
        if let nudge, nudge.isVisible, nudge.frame.intersects(box) || offScreen(nudge.frame) {
            place(nudge, "nudge")
        }
        if settings.panelPlacement == .nearMessage, let panel, panel.isVisible,
           panel.frame.intersects(box) || offScreen(panel.frame) {
            place(panel, "panel")
        }
    }

    private func place<V: View>(_ window: FloatingPanel<V>, _ name: String) {
        let spot = window.place(near: anchor)
        // Geometry only (no text), to diagnose panels landing in the wrong spot.
        let a = anchor.map { "\(Int($0.width))x\(Int($0.height))@\(Int($0.minX)),\(Int($0.minY))" } ?? "none"
        log.notice("placed \(name, privacy: .public) spot=\(spot.rawValue, privacy: .public) anchor=\(a, privacy: .public)")
    }

    /// After SwiftUI resizes a window (Why opened, rewrite arrived), keep it off the box.
    private func keepClearSoon() {
        Task { @MainActor [weak self] in self?.keepClearOfMessageBox() }
    }

    // MARK: - Heads-up chip and warm pill

    /// One small window for both quiet levels. Within a draft it only escalates
    /// (heads-up → warm), so a score wobbling between 5 and 6 doesn't flip the look.
    func showNudge(for assessment: ToneAssessment, anchor axFrame: CGRect?, runCount: Int? = nil) {
        updateAnchor(axFrame)
        hidePanel()
        let wasVisible = nudge?.isVisible == true
        let burst = runCount != nil
        var style: NudgeModel.Style = assessment.level >= .warm ? .warm : .headsUp
        if wasVisible, nudgeModel.style == .warm { style = .warm }
        if !wasVisible || style != nudgeModel.style || (nudgeModel.runCount != nil) != burst || nudgeModel.message.isEmpty {
            nudgeModel.message = switch (style, burst) {
            case (_, true): burstWarmPhrases.next()
            case (.warm, false): warmPhrases.next()
            case (.headsUp, false): headsUpPhrases.next()
            }
        }
        nudgeModel.runCount = runCount
        if !wasVisible { nudgeModel.notedMisread = false }
        nudgeModel.style = style

        if nudge == nil {
            nudge = FloatingPanel(rootView: NudgeView(
                model: nudgeModel,
                onWhy: { [weak self] in self?.actions?.explain() },
                onSoften: { [weak self] in self?.actions?.expandPill() },
                onNotHeated: { [weak self] in self?.notHeatedFromNudge() },
                onJustThisOne: { [weak self] in self?.actions?.justThisOne() },
                onClose: { [weak self] in self?.actions?.dismissForThisDraft() }
            ))
        }
        if !wasVisible, let nudge { place(nudge, "nudge") }
        nudge?.fadeIn()
        scheduleNudgeFade()
    }

    /// The nudge fades on its own, unless the user opened Why and is reading.
    private func scheduleNudgeFade() {
        nudgeHideTask?.cancel()
        // Hold still while Why is loading or being read; a failed Why fades like normal.
        switch nudgeModel.why {
        case .loading, .ready: return
        case .idle, .failed: break
        }
        let seconds: Double = nudgeModel.style == .warm ? 12 : 8
        nudgeHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.nudge?.fadeOut()
        }
    }

    // MARK: - Why

    /// Shows the Why answer on whichever surface is up. Nil-safe across both.
    func setWhy(_ state: WhyState) {
        nudgeModel.why = state
        panelModel.why = state
        if case .failed = state { scheduleNudgeFade() } else if state != .idle { nudgeHideTask?.cancel() }
        keepClearSoon()
    }

    // MARK: - Hot: panel

    func showPanel(for assessment: ToneAssessment, anchor axFrame: CGRect?, notes: String, runCount: Int? = nil) {
        updateAnchor(axFrame)
        let burst = runCount != nil
        panelModel.runCount = runCount
        nudgeHideTask?.cancel()
        nudge?.fadeOut()

        let isNew = panel?.isVisible != true
        if isNew {
            panelModel.headline = burst ? burstHotPhrases.next() : hotPhrases.next()
            panelModel.saveState = .idle
            panelModel.copied = false
            panelModel.notedMisread = false
        }
        // Keep a rewrite we already have if a re-score arrives without one.
        var assessment = assessment
        if assessment.rewrite == nil, !isNew { assessment.rewrite = panelModel.assessment?.rewrite }
        panelModel.assessment = assessment
        panelModel.notes = notes

        if panel == nil {
            panel = FloatingPanel(rootView: HotPanelView(
                model: panelModel,
                clock: motion,
                onCopy: { [weak self] text in self?.copy(text) },
                onTakeFive: { [weak self] in self?.actions?.takeFive() },
                onSave: { [weak self] in
                    guard let self, self.actions?.saveDraft() == true else { return }
                    self.panelModel.saveState = .saved
                },
                onClear: { [weak self] in
                    self?.panelModel.saveState = .cleared
                    self?.actions?.clearComposer()
                },
                onNotHeated: { [weak self] in self?.notHeatedFromPanel() },
                onWhy: { [weak self] in self?.actions?.explain() },
                onJustThisOne: { [weak self] in self?.actions?.justThisOne() },
                onDismiss: { [weak self] in self?.actions?.dismissForThisDraft() }
            ))
        }
        if isNew {
            switch settings.panelPlacement {
            case .nearMessage: if let panel { place(panel, "panel") }
            case .center: panel?.centerOnScreen(near: anchor)
            }
        }
        panel?.fadeIn()
        if MotionClock.shouldAnimate(override: settings.animateDespiteReduceMotion) {
            motion.start()
        } else {
            motion.stop()
        }
        if settings.dimForHot {
            dimmer.show(around: anchor)
        } else {
            dimmer.hide()
        }
    }

    func setRewriteLoading() {
        panelModel.rewriteLoading = true
    }

    func updateRewrite(_ rewrite: String?) {
        panelModel.rewriteLoading = false
        panelModel.assessment?.rewrite = rewrite
        keepClearSoon()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        panelModel.copied = true
    }

    // MARK: - Not heated

    /// Files the draft, says thanks briefly, then gets out of the way.
    private func notHeatedFromNudge() {
        guard actions?.markNotHeated() == true else { return }
        nudgeModel.notedMisread = true
        hideSoon { [weak self] in self?.nudge?.fadeOut() }
    }

    private func notHeatedFromPanel() {
        guard actions?.markNotHeated() == true else { return }
        panelModel.notedMisread = true
        hideSoon { [weak self] in self?.hidePanel() }
    }

    private func hideSoon(_ hide: @escaping @MainActor () -> Void) {
        nudgeHideTask?.cancel()
        nudgeHideTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    // MARK: - Take 5

    func showBreathing(anchor axFrame: CGRect?) {
        let view = BreathingView(
            endDate: Date().addingTimeInterval(5 * 60),
            onDone: { [weak self] in self?.breathing?.fadeOut() }
        )
        if let breathing {
            breathing.rootView = view
        } else {
            breathing = FloatingPanel(rootView: view)
        }
        breathing?.centerOnScreen(near: axFrame.map(AX.cocoaRect(fromAX:)))
        breathing?.fadeIn()
    }

    // MARK: - Hiding

    private func hidePanel() {
        panel?.fadeOut()
        dimmer.hide()
        motion.stop()
    }

    func hideAll() {
        nudgeHideTask?.cancel()
        nudge?.fadeOut()
        hidePanel()
    }
}
