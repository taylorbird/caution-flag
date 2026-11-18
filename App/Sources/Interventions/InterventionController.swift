import AppKit
import CooldownCore
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
}

/// Owns the floating UI: the small "warm" pill, the larger "hot" panel, and the breathing timer.
@MainActor
final class InterventionController {
    weak var actions: InterventionActions?
    private let settings: SettingsStore

    private var warmPhrases = PhraseRotator(Phrasings.warm)
    private var hotPhrases = PhraseRotator(Phrasings.hot)

    private var pill: FloatingPanel<PillView>?
    private var pillMessage: String?
    private var pillHideTask: Task<Void, Never>?

    private let panelModel = PanelModel()
    private var panel: FloatingPanel<HotPanelView>?

    private var breathing: FloatingPanel<BreathingView>?
    private var anchor: CGRect?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isShowingAnything: Bool {
        (pill?.isVisible ?? false) || (panel?.isVisible ?? false)
    }

    /// `axFrame` is in AX coordinates.
    func updateAnchor(_ axFrame: CGRect?) {
        anchor = axFrame.map(AX.cocoaRect(fromAX:))
    }

    // MARK: - Warm: pill

    func showPill(for assessment: ToneAssessment, anchor axFrame: CGRect?) {
        updateAnchor(axFrame)
        panel?.fadeOut()
        if pill?.isVisible != true || pillMessage == nil {
            pillMessage = warmPhrases.next()
        }
        let view = PillView(
            message: pillMessage ?? Phrasings.warm[0],
            canExpand: true,
            onExpand: { [weak self] in self?.actions?.expandPill() },
            onNotHeated: { [weak self] in self?.notHeatedFromPill() },
            onClose: { [weak self] in self?.actions?.dismissForThisDraft() }
        )
        if let pill {
            pill.rootView = view
        } else {
            pill = FloatingPanel(rootView: view)
        }
        pill?.position(above: anchor)
        pill?.fadeIn()

        // The pill is a nudge, not a wall: it fades on its own.
        pillHideTask?.cancel()
        pillHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.pill?.fadeOut()
        }
    }

    // MARK: - Hot: panel

    func showPanel(for assessment: ToneAssessment, anchor axFrame: CGRect?, notes: String) {
        updateAnchor(axFrame)
        pillHideTask?.cancel()
        pill?.fadeOut()

        let isNew = panel?.isVisible != true
        if isNew {
            panelModel.headline = hotPhrases.next()
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
                onDismiss: { [weak self] in self?.actions?.dismissForThisDraft() }
            ))
        }
        if isNew { panel?.position(above: anchor, alignment: .leading) }
        panel?.fadeIn()
    }

    func setRewriteLoading() {
        panelModel.rewriteLoading = true
    }

    func updateRewrite(_ rewrite: String?) {
        panelModel.rewriteLoading = false
        panelModel.assessment?.rewrite = rewrite
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        panelModel.copied = true
    }

    // MARK: - Not heated

    /// Files the draft, says thanks briefly, then gets out of the way.
    private func notHeatedFromPill() {
        guard actions?.markNotHeated() == true, let pill else { return }
        pill.rootView = PillView(message: "Noted. Thanks.", canExpand: false,
                                 onExpand: {}, onNotHeated: nil, onClose: { [weak self] in self?.pill?.fadeOut() })
        hideSoon { [weak self] in self?.pill?.fadeOut() }
    }

    private func notHeatedFromPanel() {
        guard actions?.markNotHeated() == true else { return }
        panelModel.notedMisread = true
        hideSoon { [weak self] in self?.panel?.fadeOut() }
    }

    private func hideSoon(_ hide: @escaping @MainActor () -> Void) {
        pillHideTask?.cancel()
        pillHideTask = Task {
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

    func hideAll() {
        pillHideTask?.cancel()
        pill?.fadeOut()
        panel?.fadeOut()
    }
}
