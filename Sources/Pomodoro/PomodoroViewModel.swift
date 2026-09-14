import Foundation
import Combine
import AppKit
import PomodoroCore

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

    private let engine: TimerEngine
    private let settingsStore: SettingsStore
    private let sessionLog: SessionLog
    private let driver: TimerDriving
    private let playCompletionSound: () -> Void

    /// - Parameters:
    ///   - settingsStore: Persistence for user settings (UserDefaults in prod).
    ///   - sessionLog: Durable log of completed work sessions.
    ///   - driver: Real-time tick source (injectable for tests).
    ///   - clock: Wall clock used by the engine to timestamp completions.
    ///   - playCompletionSound: Side effect fired on session completion.
    init(
        settingsStore: SettingsStore = SettingsStore(store: UserDefaults.standard),
        sessionLog: SessionLog = SessionLog(),
        driver: TimerDriving = TimerDriver(),
        clock: Clock = SystemClock(),
        playCompletionSound: @escaping () -> Void = { NSSound(named: "Glass")?.play() }
    ) {
        let loaded = settingsStore.load()
        self.settings = loaded
        self.settingsStore = settingsStore
        self.sessionLog = sessionLog
        self.driver = driver
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
        refresh()
    }

    /// Skips to the next phase (no completion event) and keeps ticking.
    func skip() {
        engine.skip()
        if case .active = engine.snapshot.phase {
            driver.start()
        }
        refresh()
    }

    /// Resets to idle and stops ticking.
    func reset() {
        engine.reset()
        // Adopt any settings edited during the just-ended session so the note
        // in SettingsView ("New durations apply after Reset") holds true.
        engine.update(config: settings.timerConfig)
        driver.stop()
        refresh()
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
    }

    private func handleCompletion(_ type: SessionType, at date: Date) {
        if type == .work {
            let session = WorkSession(completedAt: date, duration: engine.config.workDuration)
            try? sessionLog.append(session)
        }
        playCompletionSound()
        lastCompleted = type
    }

    /// Mirrors the engine's latest snapshot into the published property.
    private func refresh() {
        snapshot = engine.snapshot
    }
}
