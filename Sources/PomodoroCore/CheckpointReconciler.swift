import Foundation

/// The decision produced by reconciling a recovered ``SessionCheckpoint``
/// against the current time.
public enum ReconcileOutcome: Equatable, Sendable {
    /// The checkpoint should be thrown away with no side effects. Used for
    /// break sessions (short/long), which are not worth recovering.
    case discard
    /// A work session had already run its full duration before the crash/quit;
    /// it should be recorded to the session log as a completed session of the
    /// given duration (seconds), then the checkpoint discarded.
    case completeAndLog(duration: TimeInterval)
    /// A work session was still partially elapsed. The caller (UI) decides what
    /// to do — typically prompting the user — and may restore the engine with
    /// these values.
    ///
    /// - `remaining`: seconds left in the work session as of `now`.
    /// - `completedWorkSessions`: cycle position to restore for correct cadence.
    /// - `config`: the timer configuration the session was running under.
    case resumable(
        remaining: TimeInterval,
        completedWorkSessions: Int,
        config: TimerConfig
    )
}

/// Pure launch-time reconciliation of a recovered ``SessionCheckpoint``.
///
/// This is a stateless, side-effect-free decision function: it performs no I/O
/// and mutates nothing. Persistence (``CheckpointStore``), logging
/// (``SessionLog``) and any user prompt are the caller's responsibility, driven
/// by the returned ``ReconcileOutcome``. Keeping the policy pure makes every
/// branch trivially unit-testable with an injected `now`.
public enum CheckpointReconciler {
    /// Decides what to do with `checkpoint` given the current time `now`.
    ///
    /// Policy:
    ///  - Break sessions (short/long) -> ``ReconcileOutcome/discard``.
    ///  - Work session whose wall-clock elapsed (excluding paused time) has
    ///    reached its full duration -> ``ReconcileOutcome/completeAndLog(duration:)``.
    ///    The boundary is inclusive: elapsed exactly equal to the duration
    ///    counts as complete.
    ///  - Work session still partially elapsed ->
    ///    ``ReconcileOutcome/resumable(remaining:completedWorkSessions:config:)``.
    ///
    /// A checkpoint captured while paused accrues no further elapsed time (see
    /// ``SessionCheckpoint/elapsed(asOf:)``), so a session paused mid-work
    /// reconciles as resumable no matter how long the app was gone.
    public static func reconcile(
        checkpoint: SessionCheckpoint,
        now: Date
    ) -> ReconcileOutcome {
        guard checkpoint.sessionType == .work else {
            return .discard
        }

        let duration = checkpoint.config.duration(for: .work)
        let elapsed = checkpoint.elapsed(asOf: now)

        if elapsed >= duration {
            return .completeAndLog(duration: duration)
        }

        return .resumable(
            remaining: duration - elapsed,
            completedWorkSessions: checkpoint.completedWorkSessions,
            config: checkpoint.config
        )
    }
}
