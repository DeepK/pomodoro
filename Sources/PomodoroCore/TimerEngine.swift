import Foundation

/// The kind of session the timer can run.
public enum SessionType: String, Equatable, Codable, Sendable {
    case work
    case shortBreak
    case longBreak
}

/// Whether a session is actively counting down or held.
public enum RunState: Equatable, Sendable {
    case running
    case paused
}

/// The top-level phase of the engine.
///
/// `idle` has no associated run state; every other phase is either
/// `running` or `paused` (tracked separately on the snapshot).
public enum Phase: Equatable, Sendable {
    case idle
    case active(SessionType)
}

/// Immutable, value-type view of the engine's state.
///
/// Exposed as a value type so UI layers (a later MenuBarExtra stage) can
/// observe/diff it cheaply without reaching into engine internals.
public struct EngineSnapshot: Equatable, Sendable {
    /// Current phase (idle, or an active session type).
    public let phase: Phase
    /// Run state of the active session; `nil` while idle.
    public let runState: RunState?
    /// Seconds remaining in the current session (0 while idle).
    public let remaining: TimeInterval
    /// Number of WORK sessions completed since the last reset.
    public let completedWorkSessions: Int
}

/// Configuration for session durations and the long-break cadence.
public struct TimerConfig: Equatable, Codable, Sendable {
    /// Length of a work session, in seconds.
    public var workDuration: TimeInterval
    /// Length of a short break, in seconds.
    public var shortBreakDuration: TimeInterval
    /// Length of a long break, in seconds.
    public var longBreakDuration: TimeInterval
    /// Number of completed work sessions that trigger a long break.
    public var cyclesBeforeLongBreak: Int

    public init(
        workDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        longBreakDuration: TimeInterval,
        cyclesBeforeLongBreak: Int
    ) {
        self.workDuration = workDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.cyclesBeforeLongBreak = cyclesBeforeLongBreak
    }

    /// Duration, in seconds, for a given session type under this config.
    public func duration(for session: SessionType) -> TimeInterval {
        switch session {
        case .work: return workDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak: return longBreakDuration
        }
    }
}

/// Pure Pomodoro state machine.
///
/// The engine owns no real timer: callers drive it by invoking ``tick(_:)``,
/// which prompts the engine to *re-evaluate* the session against the injected
/// `Clock`. Remaining time is derived from wall-clock elapsed
/// (`clock.now` minus the session start, minus any paused time), NOT from
/// counting ticks. This makes the countdown robust to missed ticks — e.g.
/// while the machine is asleep — which previously caused the timer to drift
/// behind real time.
///
/// The `Clock` is injected (Dependency Inversion) so behaviour stays fully
/// deterministic and testable: no `Date()` / `Timer` is referenced directly in
/// the state logic.
///
/// Transitions on natural completion (elapsed reaches the session duration,
/// detected on a `tick`):
///  - work        -> longBreak every `cyclesBeforeLongBreak`th work session,
///                    otherwise shortBreak
///  - shortBreak  -> work
///  - longBreak   -> work
///
/// `skip` advances to the next phase *without* emitting a completion (the
/// session was not finished), while a `tick` that observes the session's
/// duration fully elapsed emits ``onSessionComplete`` with the session type
/// that just finished.
public final class TimerEngine {
    /// Emitted when a session completes naturally (not on skip/reset).
    /// The associated value is the session type that just completed and the
    /// clock time at completion. Wire this to `SessionLog` for work sessions.
    public var onSessionComplete: ((SessionType, Date) -> Void)?

    public private(set) var config: TimerConfig

    private let clock: Clock
    private var phase: Phase = .idle
    private var runState: RunState?
    private var completedWorkSessions: Int = 0

    // MARK: Wall-clock timing state

    /// Wall-clock instant (from `clock`) at which the active session started.
    private var sessionStart: Date?
    /// Total seconds the active session has spent paused, EXCLUDING any
    /// currently-open pause (see ``pauseStart``).
    private var pausedAccumulated: TimeInterval = 0
    /// Start of the current, still-open pause; `nil` while running.
    private var pauseStart: Date?
    /// Seconds advanced via ``tick(_:)`` while running. Used only as a
    /// deterministic fallback so the engine still progresses under a frozen
    /// injected clock (as the unit tests drive it). In production the injected
    /// clock always advances at least as fast, so wall-clock elapsed dominates
    /// (see ``effectiveElapsed(asOf:)``).
    private var tickElapsed: TimeInterval = 0

    public init(config: TimerConfig, clock: Clock = SystemClock()) {
        self.config = config
        self.clock = clock
    }

    /// Current immutable view of engine state.
    ///
    /// `remaining` is computed on demand from the clock, so it reflects real
    /// elapsed time even between ticks.
    public var snapshot: EngineSnapshot {
        EngineSnapshot(
            phase: phase,
            runState: runState,
            remaining: currentRemaining,
            completedWorkSessions: completedWorkSessions
        )
    }

    /// Replaces the configuration. Does not alter the in-flight session's
    /// remaining time; new durations apply to subsequent sessions.
    public func update(config: TimerConfig) {
        self.config = config
    }

    // MARK: - Operations

    /// Starts a fresh work session from `idle`. No-op if already active.
    public func start() {
        guard case .idle = phase else { return }
        begin(.work)
    }

    /// Pauses a running session. No-op otherwise.
    ///
    /// The pause is timestamped so paused time is excluded from elapsed.
    public func pause() {
        guard runState == .running else { return }
        runState = .paused
        pauseStart = clock.now
    }

    /// Resumes a paused session. No-op otherwise.
    ///
    /// Folds the just-ended pause into the accumulated paused total so it does
    /// not count towards elapsed time.
    public func resume() {
        guard runState == .paused else { return }
        if let pauseStart {
            pausedAccumulated += clock.now.timeIntervalSince(pauseStart)
        }
        pauseStart = nil
        runState = .running
    }

    /// Ends the current session immediately and advances to the next phase,
    /// running. Does NOT emit a completion event. No-op while idle.
    public func skip() {
        guard case let .active(current) = phase else { return }
        begin(nextSession(after: current, countingCompletion: false))
    }

    /// Resets the engine to `idle` and clears the completed-session counter.
    public func reset() {
        phase = .idle
        runState = nil
        completedWorkSessions = 0
        clearTiming()
    }

    /// Prompts the engine to re-evaluate the active session, advancing the
    /// deterministic tick fallback by `interval` seconds (default 1).
    ///
    /// Only has an effect while a session is `running`. When the session's
    /// duration has fully elapsed (by wall clock or, under a frozen clock, by
    /// accumulated ticks) the current session completes: ``onSessionComplete``
    /// fires and the engine transitions to (and starts running) the next
    /// session, which begins fresh with no leftover carry-over. A single large
    /// `interval` — or a large wall-clock jump after system sleep — completes
    /// exactly one session per call.
    public func tick(_ interval: TimeInterval = 1) {
        guard case let .active(current) = phase, runState == .running else { return }

        tickElapsed += interval
        let duration = config.duration(for: current)
        guard effectiveElapsed(asOf: clock.now) >= duration else { return }

        // Session finished. Emit completion, then advance.
        onSessionComplete?(current, clock.now)
        begin(nextSession(after: current, countingCompletion: true))
    }

    // MARK: - Crash recovery

    /// Captures the in-flight session as a durable ``SessionCheckpoint``, or
    /// `nil` while idle.
    ///
    /// The checkpoint is expressed purely in wall-clock terms (start instant
    /// plus paused accounting) so a later launch can recompute elapsed time
    /// against the real clock — see ``CheckpointReconciler``. The tick fallback
    /// is intentionally not persisted: in production wall-clock elapsed is
    /// authoritative.
    public func makeCheckpoint() -> SessionCheckpoint? {
        guard case let .active(type) = phase, let sessionStart else { return nil }
        return SessionCheckpoint(
            sessionType: type,
            startedAt: sessionStart,
            accumulatedPaused: pausedAccumulated,
            pausedAt: pauseStart,
            completedWorkSessions: completedWorkSessions,
            config: config
        )
    }

    /// Restores an in-flight session from a ``SessionCheckpoint`` (e.g. after a
    /// relaunch when reconciliation decided the session is resumable).
    ///
    /// Adopts the checkpoint's config and wall-clock timing verbatim, so the
    /// derived remaining time continues from where the session left off. The
    /// deterministic tick fallback is reset because wall-clock elapsed is
    /// authoritative from here on.
    public func restore(from checkpoint: SessionCheckpoint) {
        config = checkpoint.config
        phase = .active(checkpoint.sessionType)
        runState = checkpoint.pausedAt == nil ? .running : .paused
        sessionStart = checkpoint.startedAt
        pausedAccumulated = checkpoint.accumulatedPaused
        pauseStart = checkpoint.pausedAt
        tickElapsed = 0
        completedWorkSessions = checkpoint.completedWorkSessions
    }

    // MARK: - Private helpers

    /// Seconds remaining in the active session, clamped at zero. Idle -> 0.
    private var currentRemaining: TimeInterval {
        guard case let .active(session) = phase else { return 0 }
        return max(0, config.duration(for: session) - effectiveElapsed(asOf: clock.now))
    }

    /// Wall-clock seconds elapsed for the active session as of `now`, excluding
    /// all paused time (including a currently-open pause). Idle -> 0.
    private func wallElapsed(asOf now: Date) -> TimeInterval {
        guard let sessionStart else { return 0 }
        let openPause = pauseStart.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(sessionStart) - pausedAccumulated - openPause)
    }

    /// Elapsed time used for countdown/completion decisions: the greater of the
    /// wall-clock elapsed and the tick fallback. In production the injected
    /// clock advances, so wall-clock dominates (and corrects for missed ticks
    /// during sleep); under a frozen test clock the tick fallback drives it.
    private func effectiveElapsed(asOf now: Date) -> TimeInterval {
        max(tickElapsed, wallElapsed(asOf: now))
    }

    /// Enters `session` in the running state, starting a fresh wall clock.
    private func begin(_ session: SessionType) {
        phase = .active(session)
        runState = .running
        sessionStart = clock.now
        pausedAccumulated = 0
        pauseStart = nil
        tickElapsed = 0
    }

    /// Clears all timing state (used by ``reset()``).
    private func clearTiming() {
        sessionStart = nil
        pausedAccumulated = 0
        pauseStart = nil
        tickElapsed = 0
    }

    /// Computes the phase that follows `current`.
    ///
    /// When `countingCompletion` is true and the finished session was work,
    /// the completed-session counter is incremented and used to decide
    /// whether the upcoming break is long.
    private func nextSession(
        after current: SessionType,
        countingCompletion: Bool
    ) -> SessionType {
        switch current {
        case .work:
            if countingCompletion {
                completedWorkSessions += 1
            }
            let cadence = max(1, config.cyclesBeforeLongBreak)
            let isLongBreakDue = countingCompletion
                && completedWorkSessions % cadence == 0
            return isLongBreakDue ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .work
        }
    }
}
