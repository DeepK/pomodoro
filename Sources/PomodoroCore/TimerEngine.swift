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
public struct TimerConfig: Equatable, Sendable {
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
/// The engine owns no real timer: callers drive it by invoking ``tick(_:)``.
/// This keeps behaviour fully deterministic and testable. A `Clock` is
/// injected purely to timestamp completion events, so no `Date()` is called
/// directly inside the state logic.
///
/// Transitions on natural completion (remaining reaches zero via `tick`):
///  - work        -> longBreak every `cyclesBeforeLongBreak`th work session,
///                    otherwise shortBreak
///  - shortBreak  -> work
///  - longBreak   -> work
///
/// `skip` advances to the next phase *without* emitting a completion (the
/// session was not finished), while a `tick` that drains the remaining time
/// emits ``onSessionComplete`` with the session type that just finished.
public final class TimerEngine {
    /// Emitted when a session completes naturally (not on skip/reset).
    /// The associated value is the session type that just completed and the
    /// clock time at completion. Wire this to `SessionLog` for work sessions.
    public var onSessionComplete: ((SessionType, Date) -> Void)?

    public private(set) var config: TimerConfig

    private let clock: Clock
    private var phase: Phase = .idle
    private var runState: RunState?
    private var remaining: TimeInterval = 0
    private var completedWorkSessions: Int = 0

    public init(config: TimerConfig, clock: Clock = SystemClock()) {
        self.config = config
        self.clock = clock
    }

    /// Current immutable view of engine state.
    public var snapshot: EngineSnapshot {
        EngineSnapshot(
            phase: phase,
            runState: runState,
            remaining: remaining,
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
    public func pause() {
        guard runState == .running else { return }
        runState = .paused
    }

    /// Resumes a paused session. No-op otherwise.
    public func resume() {
        guard runState == .paused else { return }
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
        remaining = 0
        completedWorkSessions = 0
    }

    /// Advances time by `interval` seconds (default 1).
    ///
    /// Only has an effect while a session is `running`. When the remaining
    /// time reaches zero the current session completes: ``onSessionComplete``
    /// fires and the engine transitions to (and starts running) the next
    /// session. A single large `interval` will not skip past a boundary — it
    /// completes exactly one session and carries no remainder into the next.
    public func tick(_ interval: TimeInterval = 1) {
        guard case let .active(current) = phase, runState == .running else { return }

        remaining -= interval
        guard remaining <= 0 else { return }

        // Session finished this tick. Emit completion, then advance.
        remaining = 0
        onSessionComplete?(current, clock.now)
        begin(nextSession(after: current, countingCompletion: true))
    }

    // MARK: - Private helpers

    /// Enters `session` in the running state with a full duration.
    private func begin(_ session: SessionType) {
        phase = .active(session)
        runState = .running
        remaining = config.duration(for: session)
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
