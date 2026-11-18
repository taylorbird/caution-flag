import CooldownCore
import Foundation
import os

/// Turns a stream of draft snapshots into debounced analyses and interventions.
@MainActor
final class DraftCoordinator {
    private let settings: SettingsStore
    private let analyzers: AnalyzerProvider
    private let interventions: InterventionController
    private let status: StatusItemController
    private let capture: TextCaptureService
    private let drafts: DraftStore
    private let scorer = HeuristicScorer()
    private var heatTracker = RecentHeatTracker()
    private let log = Logger(subsystem: "com.tbird.cautionflag", category: "analysis")

    /// One continuous draft: from the first character to the field being emptied.
    private struct Session {
        let pid: pid_t
        var dismissed = false
        var countedForContext = false
        var lastAnalyzedText: String?
        var lastAssessment: ToneAssessment?
        var rewriteRequestedFor: String?
        var nextLengthTrigger = DraftCoordinator.lengthStep
    }

    static let debounce: Duration = .milliseconds(800)
    /// Analyze immediately each time the draft grows by this many characters.
    nonisolated static let lengthStep = 280
    static let modelTimeout: Double = 15

    private var session: Session?
    private var latest: DraftSnapshot?
    private var debounceTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?

    init(settings: SettingsStore, analyzers: AnalyzerProvider, interventions: InterventionController,
         status: StatusItemController, capture: TextCaptureService, drafts: DraftStore) {
        self.settings = settings
        self.analyzers = analyzers
        self.interventions = interventions
        self.status = status
        self.capture = capture
        self.drafts = drafts
        interventions.actions = self
    }

    // MARK: - Input

    func handle(_ state: CaptureState) {
        switch state {
        case .captured(let snapshot):
            handle(snapshot)
        case .noPermission:
            status.permissionMissing = true
            interventions.hideAll()
        case .notWatched, .noTextField, .secureField:
            status.permissionMissing = false
            // Leave the session intact (switching channels or apps shouldn't forget a
            // dismissal), but get out of the way.
            interventions.hideAll()
            status.level = nil
        }
    }

    private func handle(_ snapshot: DraftSnapshot) {
        status.permissionMissing = false
        let previous = latest
        latest = snapshot

        if settings.suppressionReason != nil {
            cancelWork()
            interventions.hideAll()
            status.level = nil
            return
        }

        let trimmed = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            endSession()
            return
        }
        if session == nil || session?.pid != snapshot.pid {
            session = Session(pid: snapshot.pid)
        }

        if previous?.text == snapshot.text {
            // Same draft, e.g. user came back to the app or the field moved.
            interventions.updateAnchor(snapshot.frame)
            if let assessment = session?.lastAssessment, !interventions.isShowingAnything {
                present(assessment, for: snapshot)
            }
            return
        }

        interventions.updateAnchor(snapshot.frame)
        schedule(snapshot.text)
    }

    func refreshSuppression() {
        analyzers.refresh()
        if settings.suppressionReason != nil {
            cancelWork()
            interventions.hideAll()
            status.level = nil
        }
        status.refresh()
    }

    // MARK: - Analysis

    private func schedule(_ text: String) {
        debounceTask?.cancel()
        guard var current = session else { return }
        if text.count >= current.nextLengthTrigger {
            current.nextLengthTrigger = text.count + Self.lengthStep
            session = current
            analyze(text)
            return
        }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.analyze(text)
        }
    }

    private func analyze(_ text: String) {
        guard session?.lastAnalyzedText != text else { return }
        session?.lastAnalyzedText = text
        analysisTask?.cancel()

        let report = scorer.evaluate(text)
        let combiner = ScoreCombiner(sensitivity: settings.sensitivity)
        let recent = heatTracker.count()

        guard !report.isObviouslyCalm, let analyzer = analyzers.currentAnalyzer() else {
            apply(combiner.combine(model: nil, heuristic: report, recentHeatedDrafts: recent), text: text)
            return
        }

        // Show the instant heuristic verdict now; the model can only raise it.
        let provisional = combiner.combine(model: nil, heuristic: report, recentHeatedDrafts: recent)
        if provisional.level > .calm {
            apply(provisional, text: text)
        }

        analysisTask = Task { [weak self] in
            var result: ToneResult?
            var declined = false
            do {
                result = try await withTimeout(Self.modelTimeout) { try await analyzer.analyze(text) }
                self?.analyzers.noteSuccess()
            } catch ToneAnalyzerError.declined {
                declined = true
            } catch is CancellationError {
                return
            } catch {
                self?.analyzers.noteFailure(error)
            }
            guard !Task.isCancelled, let self else { return }
            let assessment = combiner.combine(
                model: result, modelName: analyzer.displayName, modelDeclined: declined,
                heuristic: report, recentHeatedDrafts: recent
            )
            self.apply(assessment, text: text)
        }
    }

    private func apply(_ assessment: ToneAssessment, text: String) {
        guard session != nil, let snapshot = latest else { return }
        // Scores and timing only; never the text.
        log.notice("assessed score=\(assessment.score, format: .fixed(precision: 1)) level=\(assessment.level.rawValue)")
        session?.lastAssessment = assessment
        status.level = assessment.level

        if assessment.level >= .warm, session?.countedForContext == false {
            heatTracker.record()
            session?.countedForContext = true
        }
        present(assessment, for: snapshot)
    }

    private func present(_ assessment: ToneAssessment, for snapshot: DraftSnapshot) {
        guard let session else { return }
        if session.dismissed || assessment.level == .calm {
            interventions.hideAll()
            return
        }
        switch assessment.level {
        case .warm:
            interventions.showPill(for: assessment, anchor: snapshot.frame)
        case .hot:
            interventions.showPanel(for: assessment, anchor: snapshot.frame, notes: settings.personalNotes)
            fetchRewriteIfNeeded(for: snapshot.text)
        case .calm:
            break
        }
    }

    /// Rewrites are slower, so they're fetched only once the panel is up, then filled in place.
    private func fetchRewriteIfNeeded(for text: String) {
        guard session?.rewriteRequestedFor != text, let analyzer = analyzers.currentAnalyzer() else { return }
        session?.rewriteRequestedFor = text
        interventions.setRewriteLoading()
        Task { [weak self] in
            let rewrite = try? await withTimeout(Self.modelTimeout) { try await analyzer.suggestRewrite(text) }
            guard let self, self.latest?.text == text else { return }
            self.session?.lastAssessment?.rewrite = rewrite
            self.interventions.updateRewrite(rewrite)
        }
    }

    private func endSession() {
        cancelWork()
        session = nil
        interventions.hideAll()
        status.level = nil
    }

    private func cancelWork() {
        debounceTask?.cancel()
        analysisTask?.cancel()
    }
}

extension DraftCoordinator: InterventionActions {
    func dismissForThisDraft() {
        session?.dismissed = true
        interventions.hideAll()
    }

    func expandPill() {
        guard let assessment = session?.lastAssessment, let snapshot = latest else { return }
        interventions.showPanel(for: assessment, anchor: snapshot.frame, notes: settings.personalNotes)
        fetchRewriteIfNeeded(for: snapshot.text)
    }

    func takeFive() {
        session?.dismissed = true
        interventions.hideAll()
        interventions.showBreathing(anchor: latest?.frame)
    }

    func saveDraft() -> Bool {
        guard let snapshot = latest, !snapshot.text.isEmpty else { return false }
        drafts.save(text: snapshot.text, appName: snapshot.appName)
        return true
    }

    func clearComposer() {
        guard let snapshot = latest else { return }
        capture.clear(snapshot)
    }
}
