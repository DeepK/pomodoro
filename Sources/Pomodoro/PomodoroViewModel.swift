import Foundation
import Combine
import AppKit
// PomodoroCore predates Sendable annotations on its reference types (e.g.
// CheckpointStore). The clean-quit observer below is @Sendable and captures the
// store, but only ever runs on the main queue, so the capture is safe; import
// @preconcurrency to accept the pre-Sendable module rather than modify the core.
@preconcurrency import PomodoroCore

/// A completed-work-sessions bucket aggregated to a calendar week, used by the
/// reports chart's weekly mode. Daily buckets already come from
/// ``SessionLog/sessionsPerDay(lastNDays:now:calendar:)`` as `DayCount`.
struct WeekCount: Identifiable {
    /// Start-of-week date (the first day of the calendar week bucket).
    let weekStart: Date
    /// Total work sessions completed that week.
    let count: Int
    var id: Date { weekStart }
}

/// View state for the "resume interrupted session" banner shown after a crash.
///
/// Carries only what the banner needs to render (the seconds left in the work
/// session that was in flight); the checkpoint required to actually restore the
/// engine is held privately by the view model. The resume/discard *policy*
/// already ran in ``CheckpointReconciler`` — this type just backs the prompt.
struct ResumePrompt: Equatable {
    /// Seconds remaining in the interrupted work session, as of launch.
    let remaining: TimeInterval
}

/// Bridges the pure ``PomodoroCore`` modules to SwiftUI.
///
/// This is the only stateful glue between the core and the views. It owns the
/// engine, the real-time ``TimerDriving`` driver, settings persistence, and the
/// session log, and it exposes an observable ``EngineSnapshot`` plus editable
/// ``settings``. All *business* rules (transitions, long-break cadence,
/// aggregation) stay in the core — this type only forwards actions and mirrors
/// state so the UI can render it (SRP).
@MainActor
final class PomodoroViewModel: ObservableObject {
    /// Latest immutable view of the engine, republished after every mutation.
    @Published private(set) var snapshot: EngineSnapshot
    /// Editable settings, two-way bound by the settings view.
    @Published var settings: PomodoroSettings
    /// Set briefly when a session completes, so the UI can show a visual cue
    /// alongside the completion sound.
    @Published private(set) var lastCompleted: SessionType?
    /// Non-`nil` when launch reconciliation found a resumable work session that
    /// was interrupted by a crash. Drives the resume-or-discard banner; the
    /// session is NOT auto-started — the user must choose (see
    /// ``resumeInterruptedSession()`` / ``discardInterruptedSession()``).
    @Published private(set) var resumePrompt: ResumePrompt?

    private let engine: TimerEngine
    private let settingsStore: SettingsStore
    private let sessionLog: SessionLog
    private let driver: TimerDriving
    private let playCompletionSound: () -> Void
    /// Durable store for the in-flight session checkpoint (crash recovery).
    private let checkpointStore: CheckpointStore
    /// Wall clock shared with the engine; used to timestamp launch
    /// reconciliation and any session it completes-and-logs.
    private let clock: Clock
    /// The checkpoint held back while the resume banner is shown, so
    /// ``resumeInterruptedSession()`` can restore the engine from it verbatim.
    private var pendingCheckpoint: SessionCheckpoint?
    /// Set by the completion handler so the next ``tick()`` re-checkpoints the
    /// session the engine just auto-advanced into (see ``tick()``).
    private var didCompleteThisTick = false
    /// Observer that clears the checkpoint on a clean quit; a hard crash never
    /// fires it, which is exactly when the checkpoint must survive for recovery.
    private var terminationObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - settingsStore: Persistence for user settings (UserDefaults in prod).
    ///   - sessionLog: Durable log of completed work sessions.
    ///   - driver: Real-time tick source (injectable for tests).
    ///   - clock: Wall clock used by the engine to timestamp completions.
    ///   - checkpointStore: Durable store for the in-flight crash checkpoint.
    ///   - playCompletionSound: Side effect fired on session completion.
    init(
        settingsStore: SettingsStore = SettingsStore(store: UserDefaults.standard),
        sessionLog: SessionLog = SessionLog(),
        driver: TimerDriving = TimerDriver(),
        clock: Clock = SystemClock(),
        checkpointStore: CheckpointStore = CheckpointStore(),
        playCompletionSound: @escaping () -> Void = { NSSound(named: "Glass")?.play() }
    ) {
        let loaded = settingsStore.load()
        self.settings = loaded
        self.settingsStore = settingsStore
        self.sessionLog = sessionLog
        self.driver = driver
        self.clock = clock
        self.checkpointStore = checkpointStore
        self.playCompletionSound = playCompletionSound
        self.engine = TimerEngine(config: loaded.timerConfig, clock: clock)
        self.snapshot = engine.snapshot

        // Log completed WORK sessions and fire the completion side effects.
        engine.onSessionComplete = { [weak self] type, date in
            self?.handleCompletion(type, at: date)
        }
        // Each real-time tick advances the pure engine by one second.
        driver.onTick = { [weak self] in
            self?.tick()
        }

        // Crash recovery: reconcile any checkpoint left by a previous run
        // BEFORE the UI renders, then arrange to clear the checkpoint on a
        // clean quit (all policy lives in PomodoroCore; this only forwards).
        reconcileAtLaunch()
        installTerminationHook()
    }

    // MARK: - Derived state for the views

    /// True while the engine has no active session.
    var isIdle: Bool {
        if case .idle = snapshot.phase { return true }
        return false
    }

    /// True while an active session is counting down.
    var isRunning: Bool { snapshot.runState == .running }

    /// Number of work sessions before a long break (at least 1).
    var cadence: Int { max(1, engine.config.cyclesBeforeLongBreak) }

    /// 1-based position of the current work session within the cadence, used
    /// for the "2/4" cycle indicator. Counts the in-progress work session.
    var cyclePosition: Int {
        let completedInCycle = snapshot.completedWorkSessions % cadence
        if case .active(.work) = snapshot.phase {
            return completedInCycle + 1
        }
        if completedInCycle == 0 && snapshot.completedWorkSessions > 0 {
            return cadence
        }
        return completedInCycle
    }

    // MARK: - Actions (forwarded to the core)

    /// Starts a fresh work session and begins ticking.
    func start() {
        // Re-apply the latest settings so durations edited mid-session take
        // effect on the next fresh session (the engine only picks up a new
        // config between sessions, not for an in-flight one).
        engine.update(config: settings.timerConfig)
        engine.start()
        driver.start()
        // Starting a fresh session implicitly discards any interrupted session
        // the user never acted on: drop the stale banner and its checkpoint
        // BEFORE syncCheckpoint() below re-persists the NEW session's checkpoint.
        clearPendingResume()
        syncCheckpoint()
        refresh()
    }

    /// Toggles between paused and running for the active session.
    func togglePauseResume() {
        switch snapshot.runState {
        case .running:
            engine.pause()
            driver.stop()
        case .paused:
            engine.resume()
            driver.start()
        case .none:
            break
        }
        syncCheckpoint()
        refresh()
    }

    /// Skips to the next phase (no completion event) and keeps ticking.
    func skip() {
        engine.skip()
        if case .active = engine.snapshot.phase {
            driver.start()
        }
        // Defensive: also drop any lingering resume banner/checkpoint here.
        clearPendingResume()
        syncCheckpoint()
        refresh()
    }

    /// Resets to idle and stops ticking.
    func reset() {
        engine.reset()
        // Adopt any settings edited during the just-ended session so the note
        // in SettingsView ("New durations apply after Reset") holds true.
        engine.update(config: settings.timerConfig)
        driver.stop()
        // Defensive: also drop any lingering resume banner/checkpoint here.
        clearPendingResume()
        syncCheckpoint()
        refresh()
    }

    // MARK: - Crash recovery (policy lives in PomodoroCore; UI only forwards)

    /// Resumes the interrupted work session the user chose to keep.
    ///
    /// Restores the engine from the held checkpoint (continuing from the
    /// remaining time at the correct cycle position), resumes ticking if it was
    /// running, and re-persists the checkpoint for the now-live session.
    func resumeInterruptedSession() {
        guard let checkpoint = pendingCheckpoint else { return }
        engine.restore(from: checkpoint)
        pendingCheckpoint = nil
        resumePrompt = nil
        if engine.snapshot.runState == .running {
            driver.start()
        }
        syncCheckpoint()
        refresh()
    }

    /// Discards the interrupted session: clears the checkpoint and returns to
    /// the normal idle state.
    func discardInterruptedSession() {
        clearPendingResume()
        refresh()
    }

    /// Clears the held resume banner and the interrupted session's checkpoint.
    ///
    /// Shared by ``discardInterruptedSession()`` and the session actions
    /// (``start()``/``reset()``/``skip()``): once the user starts or changes a
    /// session, the interrupted one is implicitly discarded. Callers that
    /// ``syncCheckpoint()`` immediately afterwards re-persist the NEW session's
    /// checkpoint, so the ``checkpointStore/clear()`` here only drops the stale
    /// one. Guarded so the common no-prompt path does no I/O or extra publish.
    private func clearPendingResume() {
        guard resumePrompt != nil || pendingCheckpoint != nil else { return }
        checkpointStore.clear()
        pendingCheckpoint = nil
        resumePrompt = nil
    }

    // MARK: - Settings

    /// Persists the current ``settings`` and, when the engine is idle, applies
    /// them to the engine config immediately. While a session is active the new
    /// config is stored and takes effect on the next reset/start, matching the
    /// core's rule that in-flight sessions keep their original durations.
    func persistSettings() {
        try? settingsStore.save(settings)
        if isIdle {
            engine.update(config: settings.timerConfig)
            refresh()
        }
    }

    // MARK: - Reports (aggregation lives in SessionLog)

    /// Zero-filled daily counts for the last `days` days, oldest first.
    func dailyCounts(days: Int) -> [DayCount] {
        (try? sessionLog.sessionsPerDay(lastNDays: days)) ?? []
    }

    /// Weekly totals for the last `weeks` calendar weeks, oldest first and
    /// including the current (possibly partial) week.
    ///
    /// Each bucket's `weekStart` is a real calendar week boundary from
    /// `calendar.dateInterval(of: .weekOfYear, ...)`, so it lines up with the
    /// chart's `.weekOfYear` x-binning (rolling 7-day chunks did not).
    func weeklyCounts(weeks: Int) -> [WeekCount] {
        guard weeks >= 1 else { return [] }
        let calendar = Calendar.current
        let now = Date()

        // Start-of-week for each of the last `weeks` calendar weeks, oldest
        // first (offset 0 == the current week).
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return []
        }
        var weekStarts: [Date] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let start = calendar.date(
                byAdding: .weekOfYear,
                value: -offset,
                to: currentWeek.start
            ) else { continue }
            weekStarts.append(start)
        }
        guard let earliest = weekStarts.first else { return [] }

        // Pull enough daily buckets to span the earliest week start through
        // today, then fold each day into the calendar week that contains it.
        let spanDays = (calendar.dateComponents(
            [.day],
            from: earliest,
            to: calendar.startOfDay(for: now)
        ).day ?? 0) + 1
        let days = (try? sessionLog.sessionsPerDay(
            lastNDays: spanDays,
            now: now,
            calendar: calendar
        )) ?? []

        var countsByWeekStart: [Date: Int] = [:]
        for day in days {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: day.date) else {
                continue
            }
            countsByWeekStart[interval.start, default: 0] += day.count
        }

        return weekStarts.map {
            WeekCount(weekStart: $0, count: countsByWeekStart[$0] ?? 0)
        }
    }

    // MARK: - Private

    private func tick() {
        engine.tick(1)
        refresh()
        // When a session completes, the engine auto-advances into the next one
        // (see TimerEngine.tick). Re-checkpoint so the stored checkpoint tracks
        // the now-current session rather than the finished one — otherwise a
        // later crash would re-complete-and-log the already-finished session.
        if didCompleteThisTick {
            didCompleteThisTick = false
            syncCheckpoint()
        }
    }

    private func handleCompletion(_ type: SessionType, at date: Date) {
        if type == .work {
            let session = WorkSession(completedAt: date, duration: engine.config.workDuration)
            try? sessionLog.append(session)
        }
        playCompletionSound()
        lastCompleted = type
        // The engine transitions to the next session immediately after this
        // callback; defer the re-checkpoint to tick() once that has happened.
        didCompleteThisTick = true
    }

    /// Mirrors the engine's latest snapshot into the published property.
    private func refresh() {
        snapshot = engine.snapshot
    }

    // MARK: - Crash recovery internals

    /// Persists the current in-flight session as a checkpoint, or clears the
    /// stored checkpoint when the engine is idle. Called after every action
    /// that starts, changes, or ends a session.
    private func syncCheckpoint() {
        if let checkpoint = engine.makeCheckpoint() {
            try? checkpointStore.save(checkpoint)
        } else {
            checkpointStore.clear()
        }
    }

    /// Loads any checkpoint left by a previous run and applies the pure
    /// ``CheckpointReconciler`` decision. All policy (discard vs.
    /// complete-and-log vs. resumable) lives in the core; this only performs
    /// the resulting I/O and, for a resumable session, holds it back for the
    /// user's explicit choice rather than auto-starting.
    private func reconcileAtLaunch() {
        guard let checkpoint = checkpointStore.load() else { return }
        switch CheckpointReconciler.reconcile(checkpoint: checkpoint, now: clock.now) {
        case .discard:
            checkpointStore.clear()
        case .completeAndLog(let duration):
            // The work portion finished at start + paused time + duration; log
            // it there so it lands in the correct day bucket for reports.
            let completedAt = checkpoint.startedAt
                .addingTimeInterval(checkpoint.accumulatedPaused + duration)
            // Use the idempotent variant: a crash in the sub-ms window between
            // handleCompletion's append and the checkpoint overwrite leaves a
            // stale fully-elapsed WORK checkpoint whose synthesized completedAt
            // matches the already-logged entry. appendIfAbsent skips that
            // duplicate so recovery never double-counts a session.
            _ = try? sessionLog.appendIfAbsent(
                WorkSession(completedAt: completedAt, duration: duration)
            )
            checkpointStore.clear()
        case .resumable(let remaining, _, _):
            // Keep the checkpoint (do NOT clear) so the user can resume; expose
            // just the remaining time to the banner.
            pendingCheckpoint = checkpoint
            resumePrompt = ResumePrompt(remaining: remaining)
        }
    }

    /// Clears the checkpoint on a clean quit (e.g. the popover's Quit button,
    /// which calls `NSApplication.terminate`). A hard crash never posts this
    /// notification, so the checkpoint survives precisely when recovery is
    /// wanted; a clean quit removes it so the next launch starts fresh.
    ///
    /// Feasibility note: this fires reliably for the MenuBarExtra app because
    /// `NSApplication.terminate(_:)` posts `willTerminate` synchronously even
    /// for a non-bundled Command Line Tools executable.
    private func installTerminationHook() {
        let store = checkpointStore
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            store.clear()
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }
}
