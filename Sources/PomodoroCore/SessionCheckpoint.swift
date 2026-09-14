import Foundation

/// A durable snapshot of an in-flight session, sufficient to reconcile — and,
/// when appropriate, resume — it after a crash or relaunch.
///
/// Timing is expressed in wall-clock terms (a session start `Date` plus paused
/// accounting) rather than a remaining-seconds countdown, so elapsed time can
/// be recomputed against the real clock on the next launch — correctly
/// accounting for time the app spent dead or the machine spent asleep.
///
/// Single responsibility: this is a plain, `Codable` value. It carries no
/// behaviour beyond deriving its own elapsed time; persistence lives in
/// ``CheckpointStore`` and the resume/complete/discard decision lives in
/// ``CheckpointReconciler``.
public struct SessionCheckpoint: Codable, Equatable, Sendable {
    /// The session type in flight when the checkpoint was written.
    public let sessionType: SessionType
    /// Wall-clock instant the session started running.
    public let startedAt: Date
    /// Total seconds the session had spent paused, EXCLUDING any pause still
    /// open when the checkpoint was written (see ``pausedAt``).
    public let accumulatedPaused: TimeInterval
    /// If the session was paused when the checkpoint was written, the instant
    /// that (still-open) pause began; `nil` if it was running. A checkpoint
    /// captured while paused accrues no further elapsed time until resumed.
    public let pausedAt: Date?
    /// Completed WORK sessions before this one — the engine's cycle position,
    /// needed to keep the long-break cadence correct on resume.
    public let completedWorkSessions: Int
    /// The ``TimerConfig`` in effect for this session.
    public let config: TimerConfig

    public init(
        sessionType: SessionType,
        startedAt: Date,
        accumulatedPaused: TimeInterval,
        pausedAt: Date?,
        completedWorkSessions: Int,
        config: TimerConfig
    ) {
        self.sessionType = sessionType
        self.startedAt = startedAt
        self.accumulatedPaused = accumulatedPaused
        self.pausedAt = pausedAt
        self.completedWorkSessions = completedWorkSessions
        self.config = config
    }

    /// Wall-clock seconds actually elapsed for this session as of `now`,
    /// excluding all paused time, clamped at zero.
    ///
    /// A checkpoint captured while paused (``pausedAt`` non-`nil`) freezes here:
    /// the open pause grows in lockstep with `now`, so no further elapsed time
    /// accrues until the session is resumed.
    public func elapsed(asOf now: Date) -> TimeInterval {
        let openPause = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - accumulatedPaused - openPause)
    }
}
