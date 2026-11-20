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
    /// The conversation the run's sends went to; a send elsewhere starts a fresh run.
    private var burstConversation: String?
    /// Whether the last change to the draft removed text (e.g. held Delete),
    /// so emptying the field next is a deletion, not a send.
    private var wasShrinking = false
    private let log = Logger(subsystem: "com.tbird.cautionflag", category: "analysis")

    /// One continuous draft: from the first character to the field being emptied.
    private struct Session {
        let id = UUID()
        let pid: pid_t
        var dismissed = false
        var countedForContext = false
        var lastAnalyzedText: String?
        var lastAssessment: ToneAssessment?
        var rewriteRequestedFor: String?
        /// Earlier messages in a quick run, scored together with this draft.
        var burstContext: [String]?
        /// The run read clearly hotter than the draft alone, so the flag is the run's.
        var runApplies = false
        /// "Just this one": judge this draft on its own for the rest of it.
        var ignoreRun = false
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
    /// The on-demand "Why?" call. Never started by typing, only by a tap.
    private var explainTask: Task<Void, Never>?

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
                noteSend(previous.text, pid: snapshot.pid, conversation: previous.conversation)
            }
            endSession()
            return
        }
        if session == nil || session?.pid != snapshot.pid
            || (samePid && previous.map { Self.isReplacement(of: $0.text, by: snapshot.text) } == true) {
            session = Session(pid: snapshot.pid)
            explainTask?.cancel()
            explainTask = nil
            interventions.setWhy(.idle)
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
        if settings.noticeBursts {
            bursts.configure(level: settings.burstSensitivity)
            _ = bursts.context()
        } else {
            bursts.reset()
        }
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

    private func noteSend(_ text: String, pid: pid_t, conversation: String) {
        guard settings.noticeBursts else {
            bursts.reset()
            return
        }
        bursts.configure(level: settings.burstSensitivity)
        if burstPid != pid || burstConversation != conversation {
            bursts.reset()
            burstPid = pid
            burstConversation = conversation
        }
        bursts.recordSend(text)
        log.notice("send noticed length=\(text.count) runSends=\(self.bursts.sendCount) conv=\(DraftSnapshot.tag(conversation), privacy: .public)")
    }

    /// The earlier messages of a quick run in this conversation, if one is underway.
    private func burstContext() -> [String]? {
        guard settings.noticeBursts, session?.ignoreRun == false, let pid = session?.pid, pid == burstPid,
              latest?.conversation == burstConversation else { return nil }
        bursts.configure(level: settings.burstSensitivity)
        return bursts.context()
    }

    /// What gets scored: the draft alone, or the run plus the draft.
    private func scoredText(for text: String) -> String {
        session?.burstContext.map { BurstTracker.combined($0, draft: text) } ?? text
    }

    /// What the flag is about, for the rewrite, Why? and Not heated: the run only when
    /// the run is what made it hot.
    private func presentedText(for text: String) -> String {
        session?.runApplies == true ? scoredText(for: text) : text
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

        // Show the instant heuristic verdict now; the model can only raise it. Judged on the
        // draft alone: a run only gets credit once the model has compared the two.
        let provisional = combiner.combine(model: nil, heuristic: isBurst ? scorer.evaluate(text) : report,
                                           recentHeatedDrafts: recent)
        if provisional.level > .calm {
            apply(provisional, text: text)
        }

        // While Why? is asking the model, typing scores wait: Apple's model rejects a
        // second request at once, which is what made Why? fail in 0.1.4.
        if analysisTask == nil, explainTask == nil {
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
        let isBurst = session?.burstContext != nil

        analysisTask = Task { [weak self] in
            let clock = ContinuousClock()
            let started = clock.now
            guard let first = await self?.score(scored, with: analyzer) else { return }
            guard !Task.isCancelled, let self else { return }
            // Timing and length only; never the text.
            self.log.notice("model scored in \(Int((clock.now - started) / .milliseconds(1))) ms length=\(scored.count)")
            var assessment = combiner.combine(
                model: first.result, modelName: analyzer.displayName, modelDeclined: first.declined,
                heuristic: report, recentHeatedDrafts: recent
            )
            var runApplies = false
            if isBurst, assessment.level > .calm {
                // The run flagged it; does the draft alone read nearly as hot? Then the
                // draft is the story and the run gets no credit (one extra call, only here).
                guard let solo = await self.score(text, with: analyzer), !Task.isCancelled else { return }
                let alone = combiner.combine(
                    model: solo.result, modelName: analyzer.displayName, modelDeclined: solo.declined,
                    heuristic: self.scorer.evaluate(text), recentHeatedDrafts: recent
                )
                runApplies = RunDecision.runApplies(combined: assessment, alone: alone)
                self.log.notice("run check combined=\(assessment.score, format: .fixed(precision: 1)) alone=\(alone.score, format: .fixed(precision: 1)) runApplies=\(runApplies)")
                if !runApplies { assessment = alone }
            }
            self.analysisTask = nil
            if self.session?.runApplies != runApplies {
                // What the flag is about changed (run vs. draft); an earlier rewrite no longer fits.
                self.session?.rewriteRequestedFor = nil
                self.session?.lastAssessment?.rewrite = nil
                self.rewriteTask?.cancel()
                self.rewriteTask = nil
                self.interventions.updateRewrite(nil)
            }
            self.session?.runApplies = runApplies
            self.apply(assessment, text: text)

            // Catch up to whatever was typed meanwhile (unless Why? is now running;
            // it picks the queue back up when it finishes).
            if self.explainTask == nil, let next = self.queuedText {
                self.queuedText = nil
                if next != text { self.startModelScore(next) }
            }
        }
    }

    /// One model call. Nil only when cancelled.
    private func score(_ text: String, with analyzer: ToneAnalyzer) async -> (result: ToneResult?, declined: Bool)? {
        do {
            let result = try await withTimeout(Self.modelTimeout) { try await analyzer.analyze(text) }
            analyzers.noteSuccess()
            return (result, false)
        } catch ToneAnalyzerError.declined {
            return (nil, true)
        } catch is CancellationError {
            return nil
        } catch {
            analyzers.noteFailure(error)
            // The error's kind only; never text.
            let kind = (error as? ToneAnalyzerError)?.kind ?? "other"
            log.notice("model failed kind=\(kind, privacy: .public)")
            return (nil, false)
        }
    }

    private func apply(_ assessment: ToneAssessment, text: String) {
        guard session != nil, let snapshot = latest else { return }
        // Scores and timing only; never the text.
        log.notice("assessed score=\(assessment.score, format: .fixed(precision: 1)) level=\(assessment.level.name, privacy: .public) runContext=\(self.session?.burstContext?.count ?? 0) runApplies=\(self.session?.runApplies == true)")
        session?.lastAssessment = assessment
        status.level = assessment.level

        // Heads-up counts too: the "rough stretch" rule kept its original 4+ threshold.
        if assessment.level >= .headsUp, session?.countedForContext == false {
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
        let runCount = session.runApplies ? session.burstContext?.count : nil
        switch assessment.level {
        case .headsUp, .warm:
            interventions.showNudge(for: assessment, anchor: snapshot.frame, runCount: runCount)
        case .hot:
            interventions.showPanel(for: assessment, anchor: snapshot.frame, notes: settings.personalNotes, runCount: runCount)
            fetchRewriteIfNeeded(for: snapshot.text)
        case .calm:
            break
        }
    }

    /// Rewrites are slower, so they're fetched only once the panel is up, then filled in place.
    private func fetchRewriteIfNeeded(for text: String) {
        // For a quick run, the calmer version gathers the whole run into one message.
        let target = presentedText(for: text)
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
        interventions.setWhy(.idle)
        interventions.hideAll()
        status.level = nil
    }

    private func cancelWork() {
        analysisTask?.cancel()
        analysisTask = nil
        queuedText = nil
        rewriteTask?.cancel()
        rewriteTask = nil
        explainTask?.cancel()
        explainTask = nil
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
                                runCount: session?.runApplies == true ? session?.burstContext?.count : nil)
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
        misreads.record(text: presentedText(for: snapshot.text), appName: snapshot.appName, assessment: assessment,
                        sensitivity: settings.sensitivity, burst: session?.runApplies == true)
        // Quiet for the rest of this draft, but the controller hides the UI after a brief thanks.
        session?.dismissed = true
        log.notice("misread filed score=\(assessment.score, format: .fixed(precision: 1)) level=\(assessment.level.name, privacy: .public)")
        return true
    }

    func explain() {
        guard explainTask == nil, let session, let assessment = session.lastAssessment, let snapshot = latest,
              let analyzer = analyzers.currentAnalyzer() else {
            if analyzers.currentAnalyzer() == nil {
                interventions.setWhy(.failed("The on-device model isn't available right now, so there's no closer look to give."))
            }
            return
        }
        let target = presentedText(for: snapshot.text)
        let sessionID = session.id
        interventions.setWhy(.loading)
        let inFlight = analysisTask
        explainTask = Task { [weak self] in
            let clock = ContinuousClock()
            let started = clock.now
            // Let a typing score already in flight finish first; new ones wait for us.
            await inFlight?.value
            var state = WhyState.failed("Couldn't get a closer look just now. Try Why? again in a moment.")
            var attempts = 0
            retry: while attempts < 3 {
                attempts += 1
                do {
                    let why = try await withTimeout(Self.modelTimeout) { try await analyzer.explain(target, assessment: assessment) }
                    state = .ready(why)
                    break retry
                } catch ToneAnalyzerError.busy {
                    // Busy or rate-limited: back off and try again.
                    try? await Task.sleep(for: .milliseconds(700 * attempts))
                    if Task.isCancelled { return }
                    continue retry
                } catch is CancellationError {
                    return
                } catch {
                    state = Self.whyFailure(error)
                    if let e = error as? ToneAnalyzerError { self?.log.notice("explain failed kind=\(e.kind, privacy: .public)") }
                    break retry
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.explainTask = nil
            // Timing and outcome only; never the text or the explanation.
            let outcome = if case .ready = state { "ok" } else { "failed" }
            self.log.notice("explained in \(Int((clock.now - started) / .milliseconds(1))) ms outcome=\(outcome, privacy: .public) attempts=\(attempts)")
            // Scores that waited while Why? ran pick up now.
            if self.analysisTask == nil, let next = self.queuedText {
                self.queuedText = nil
                self.startModelScore(next)
            }
            guard self.session?.id == sessionID else { return }
            self.interventions.setWhy(state)
        }
    }

    private static func whyFailure(_ error: Error) -> WhyState {
        switch error {
        case ToneAnalyzerError.declined:
            .failed("Apple's on-device safety filter wouldn't look at this one. A single word can trip it, so it doesn't mean the draft is heated.")
        case ToneAnalyzerError.timeout:
            .failed("That took too long. Try Why? again in a moment.")
        default:
            .failed("Couldn't get a closer look just now. Try Why? again in a moment.")
        }
    }

    /// "Just this one": drop the run and judge the draft on its own from here on.
    func justThisOne() {
        guard session != nil, let snapshot = latest else { return }
        analysisTask?.cancel()
        analysisTask = nil
        queuedText = nil
        session?.ignoreRun = true
        session?.burstContext = nil
        session?.runApplies = false
        session?.lastAnalyzedText = nil
        session?.lastAssessment = nil
        session?.rewriteRequestedFor = nil
        explainTask?.cancel()
        explainTask = nil
        // A rewrite in flight was for the whole run; drop it so the draft gets its own.
        rewriteTask?.cancel()
        rewriteTask = nil
        interventions.updateRewrite(nil)
        interventions.setWhy(.idle)
        interventions.hideAll()
        log.notice("run dropped for this draft")
        analyze(snapshot.text)
    }

    func clearComposer() {
        guard let snapshot = latest else { return }
        capture.clear(snapshot)
    }
}
