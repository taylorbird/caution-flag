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
    private let misreads: MisreadStore
    private let scorer = HeuristicScorer()
    private var heatTracker = RecentHeatTracker()
    /// Recently sent messages, in memory only, for noticing quick runs.
    private var bursts = BurstTracker()
    private var burstPid: pid_t?
    /// Whether the last change to the draft removed text (e.g. held Delete),
    /// so emptying the field next is a deletion, not a send.
    private var wasShrinking = false
    private let log = Logger(subsystem: "com.tbird.cautionflag", category: "analysis")

    /// One continuous draft: from the first character to the field being emptied.
    private struct Session {
        let pid: pid_t
        var dismissed = false
        var countedForContext = false
        var lastAnalyzedText: String?
        var lastAssessment: ToneAssessment?
        var rewriteRequestedFor: String?
        /// Earlier messages in a quick run, scored together with this draft.
        var burstContext: [String]?
    }

    static let modelTimeout: Double = 15

    private var session: Session?
    private var latest: DraftSnapshot?
    /// The one model score in flight. Scoring runs continuously while typing: a new
    /// keystroke never cancels it; the newest text waits in `queuedText` and is scored
    /// as soon as the model is free, so a nudge can land before the user pauses.
    private var analysisTask: Task<Void, Never>?
    private var queuedText: String?
    private var rewriteTask: Task<Void, Never>?

    init(settings: SettingsStore, analyzers: AnalyzerProvider, interventions: InterventionController,
         status: StatusItemController, capture: TextCaptureService, drafts: DraftStore,
         misreads: MisreadStore) {
        self.settings = settings
        self.analyzers = analyzers
        self.interventions = interventions
        self.status = status
        self.capture = capture
        self.drafts = drafts
        self.misreads = misreads
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
        let samePid = previous?.pid == snapshot.pid
        let shrankBefore = wasShrinking
        wasShrinking = samePid && snapshot.text.count < (previous?.text.count ?? 0)

        if settings.suppressionReason != nil {
            bursts.reset()
            cancelWork()
            interventions.hideAll()
            status.level = nil
            return
        }

        let trimmed = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Text that vanishes in one step (not after a run of deletions) was sent.
            if samePid, !shrankBefore, let previous,
               previous.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                noteSend(previous.text, pid: snapshot.pid)
            }
            endSession()
            return
        }
        if session == nil || session?.pid != snapshot.pid
            || (samePid && previous.map { Self.isReplacement(of: $0.text, by: snapshot.text) } == true) {
            session = Session(pid: snapshot.pid)
            // A new draft: get the model loaded while the first words are typed.
            analyzers.currentAnalyzer()?.prepare()
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
        analyze(snapshot.text)
    }

    /// Select-all and typing over a draft never empties the field, so it would otherwise
    /// count as the same draft and inherit "dismissed". A change that, in one step,
    /// shares less than the first two characters with a draft of some length is a new one.
    /// Deleting with Backspace keeps the start intact, so it stays the same draft.
    nonisolated static func isReplacement(of old: String, by new: String) -> Bool {
        let old = old.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard old.count >= 8, !new.isEmpty else { return false }
        let shared = zip(old, new).prefix { $0 == $1 }.count
        return shared < 2
    }

    func refreshSuppression() {
        // Runs every 30 s: let sent text age out of memory even if nothing else happens.
        if settings.noticeBursts { _ = bursts.context() } else { bursts.reset() }
        analyzers.refresh()
        if settings.suppressionReason != nil {
            bursts.reset()
            cancelWork()
            interventions.hideAll()
            status.level = nil
        }
        status.refresh()
    }

    // MARK: - Quick runs

    private func noteSend(_ text: String, pid: pid_t) {
        guard settings.noticeBursts else {
            bursts.reset()
            return
        }
        if burstPid != pid {
            bursts.reset()
            burstPid = pid
        }
        bursts.recordSend(text)
        log.notice("send noticed length=\(text.count) runSends=\(self.bursts.sendCount)")
    }

    /// The earlier messages of a quick run in this app, if one is underway.
    private func burstContext() -> [String]? {
        guard settings.noticeBursts, let pid = session?.pid, pid == burstPid else { return nil }
        return bursts.context()
    }

    /// What gets scored and rewritten: the draft alone, or the run plus the draft.
    private func scoredText(for text: String) -> String {
        session?.burstContext.map { BurstTracker.combined($0, draft: text) } ?? text
    }

    // MARK: - Analysis

    /// Runs on every change to the draft. The heuristic verdict is instant; the model
    /// score starts now if the model is free, otherwise right after the current one.
    private func analyze(_ text: String) {
        guard session?.lastAnalyzedText != text else { return }
        session?.lastAnalyzedText = text

        // Read first: assigning through `session?.` while burstContext() reads `session`
        // is an exclusivity conflict, which aborts the app.
        let context = burstContext()
        session?.burstContext = context
        let scored = scoredText(for: text)
        let isBurst = session?.burstContext != nil
        let report = scorer.evaluate(scored)
        let combiner = ScoreCombiner(sensitivity: settings.sensitivity)
        let recent = heatTracker.count()

        // A run of short messages can each look obviously calm, so always ask the model.
        guard isBurst || !report.isObviouslyCalm, analyzers.currentAnalyzer() != nil else {
            apply(combiner.combine(model: nil, heuristic: report, recentHeatedDrafts: recent), text: text)
            return
        }

        // Show the instant heuristic verdict now; the model can only raise it.
        let provisional = combiner.combine(model: nil, heuristic: report, recentHeatedDrafts: recent)
        if provisional.level > .calm {
            apply(provisional, text: text)
        }

        if analysisTask == nil {
            startModelScore(text)
        } else {
            queuedText = text
        }
    }

    private func startModelScore(_ text: String) {
        guard let analyzer = analyzers.currentAnalyzer() else { return }
        let scored = scoredText(for: text)
        let report = scorer.evaluate(scored)
        let combiner = ScoreCombiner(sensitivity: settings.sensitivity)
        let recent = heatTracker.count()

        analysisTask = Task { [weak self] in
            var result: ToneResult?
            var declined = false
            let clock = ContinuousClock()
            let started = clock.now
            do {
                result = try await withTimeout(Self.modelTimeout) { try await analyzer.analyze(scored) }
                self?.analyzers.noteSuccess()
            } catch ToneAnalyzerError.declined {
                declined = true
            } catch is CancellationError {
                return
            } catch {
                self?.analyzers.noteFailure(error)
            }
            guard !Task.isCancelled, let self else { return }
            let ms = Int((clock.now - started) / .milliseconds(1))
            // Timing and length only; never the text.
            self.log.notice("model scored in \(ms) ms length=\(scored.count)")
            self.analysisTask = nil
            let assessment = combiner.combine(
                model: result, modelName: analyzer.displayName, modelDeclined: declined,
                heuristic: report, recentHeatedDrafts: recent
            )
            self.apply(assessment, text: text)

            // Catch up to whatever was typed meanwhile.
            if let next = self.queuedText {
                self.queuedText = nil
                if next != text { self.startModelScore(next) }
            }
        }
    }

    private func apply(_ assessment: ToneAssessment, text: String) {
        guard session != nil, let snapshot = latest else { return }
        // Scores and timing only; never the text.
        log.notice("assessed score=\(assessment.score, format: .fixed(precision: 1)) level=\(assessment.level.rawValue) runContext=\(self.session?.burstContext?.count ?? 0)")
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
        let burst = session.burstContext != nil
        switch assessment.level {
        case .warm:
            interventions.showPill(for: assessment, anchor: snapshot.frame, burst: burst)
        case .hot:
            interventions.showPanel(for: assessment, anchor: snapshot.frame, notes: settings.personalNotes, burst: burst)
            fetchRewriteIfNeeded(for: snapshot.text)
        case .calm:
            break
        }
    }

    /// Rewrites are slower, so they're fetched only once the panel is up, then filled in place.
    private func fetchRewriteIfNeeded(for text: String) {
        // For a quick run, the calmer version gathers the whole run into one message.
        let target = scoredText(for: text)
        // One rewrite at a time: while typing continues under an open panel, the next
        // score after this one finishes asks again for the newer text.
        guard rewriteTask == nil, session?.rewriteRequestedFor != target,
              let analyzer = analyzers.currentAnalyzer() else { return }
        session?.rewriteRequestedFor = target
        if session?.lastAssessment?.rewrite == nil { interventions.setRewriteLoading() }
        rewriteTask = Task { [weak self] in
            let clock = ContinuousClock()
            let started = clock.now
            let rewrite = try? await withTimeout(Self.modelTimeout) { try await analyzer.suggestRewrite(target) }
            guard !Task.isCancelled, let self else { return }
            self.rewriteTask = nil
            self.log.notice("rewrite in \(Int((clock.now - started) / .milliseconds(1))) ms")
            guard self.session != nil else { return }
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
        analysisTask?.cancel()
        analysisTask = nil
        queuedText = nil
        rewriteTask?.cancel()
        rewriteTask = nil
    }
}

extension DraftCoordinator: InterventionActions {
    func dismissForThisDraft() {
        session?.dismissed = true
        interventions.hideAll()
    }

    func expandPill() {
        guard let assessment = session?.lastAssessment, let snapshot = latest else { return }
        interventions.showPanel(for: assessment, anchor: snapshot.frame, notes: settings.personalNotes,
                                burst: session?.burstContext != nil)
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

    func markNotHeated() -> Bool {
        guard let snapshot = latest, !snapshot.text.isEmpty, let assessment = session?.lastAssessment else { return false }
        misreads.record(text: scoredText(for: snapshot.text), appName: snapshot.appName, assessment: assessment,
                        sensitivity: settings.sensitivity, burst: session?.burstContext != nil)
        // Quiet for the rest of this draft, but the controller hides the UI after a brief thanks.
        session?.dismissed = true
        log.notice("misread filed score=\(assessment.score, format: .fixed(precision: 1)) level=\(assessment.level.rawValue)")
        return true
    }

    func clearComposer() {
        guard let snapshot = latest else { return }
        capture.clear(snapshot)
    }
}
