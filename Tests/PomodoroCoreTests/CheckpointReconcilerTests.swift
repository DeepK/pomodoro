import Testing
import Foundation
@testable import PomodoroCore

// See TimerEngineTests for why these use swift-testing (`import Testing`).

@Suite struct CheckpointReconcilerTests {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// 25m work, 5m short, 15m long, long break every 4th work session.
    private func makeConfig() -> TimerConfig {
        TimerConfig(
            workDuration: 25 * 60,
            shortBreakDuration: 5 * 60,
            longBreakDuration: 15 * 60,
            cyclesBeforeLongBreak: 4
        )
    }

    private func checkpoint(
        type: SessionType,
        startedAt: Date,
        accumulatedPaused: TimeInterval = 0,
        pausedAt: Date? = nil,
        completedWorkSessions: Int = 0
    ) -> SessionCheckpoint {
        SessionCheckpoint(
            sessionType: type,
            startedAt: startedAt,
            accumulatedPaused: accumulatedPaused,
            pausedAt: pausedAt,
            completedWorkSessions: completedWorkSessions,
            config: makeConfig()
        )
    }

    @Test func shortBreakIsDiscarded() {
        let start = date("2026-09-14T10:00:00Z")
        let cp = checkpoint(type: .shortBreak, startedAt: start)
        #expect(CheckpointReconciler.reconcile(checkpoint: cp, now: start.addingTimeInterval(10)) == .discard)
    }

    @Test func longBreakIsDiscarded() {
        let start = date("2026-09-14T10:00:00Z")
        let cp = checkpoint(type: .longBreak, startedAt: start)
        #expect(CheckpointReconciler.reconcile(checkpoint: cp, now: start.addingTimeInterval(10)) == .discard)
    }

    @Test func fullyElapsedWorkCompletesAndLogs() {
        let start = date("2026-09-14T10:00:00Z")
        let cp = checkpoint(type: .work, startedAt: start, completedWorkSessions: 1)
        // 30 minutes later: past the 25m work duration.
        let outcome = CheckpointReconciler.reconcile(checkpoint: cp, now: start.addingTimeInterval(30 * 60))
        #expect(outcome == .completeAndLog(duration: 25 * 60))
    }

    @Test func workExactlyAtBoundaryCompletes() {
        let start = date("2026-09-14T10:00:00Z")
        let cp = checkpoint(type: .work, startedAt: start)
        // Elapsed exactly equal to the duration counts as complete (inclusive).
        let outcome = CheckpointReconciler.reconcile(checkpoint: cp, now: start.addingTimeInterval(25 * 60))
        #expect(outcome == .completeAndLog(duration: 25 * 60))
    }

    @Test func partiallyElapsedWorkIsResumable() {
        let start = date("2026-09-14T10:00:00Z")
        let cp = checkpoint(type: .work, startedAt: start, completedWorkSessions: 2)
        // 10 minutes in: 15 minutes remain.
        let outcome = CheckpointReconciler.reconcile(checkpoint: cp, now: start.addingTimeInterval(10 * 60))
        #expect(outcome == .resumable(remaining: 15 * 60, completedWorkSessions: 2, config: makeConfig()))
    }

    @Test func pausedTimeIsExcludedFromElapsed() {
        let start = date("2026-09-14T10:00:00Z")
        // 5 minutes of accumulated paused time before the crash.
        let cp = checkpoint(type: .work, startedAt: start, accumulatedPaused: 5 * 60)
        // 20 wall-clock minutes later, but 5 were paused -> 15m elapsed -> 10m remain.
        let outcome = CheckpointReconciler.reconcile(checkpoint: cp, now: start.addingTimeInterval(20 * 60))
        #expect(outcome == .resumable(remaining: 10 * 60, completedWorkSessions: 0, config: makeConfig()))
    }

    @Test func checkpointPausedAtCrashFreezesElapsedAndStaysResumable() {
        let start = date("2026-09-14T10:00:00Z")
        // Paused 8 minutes into the work session; the pause is still open.
        let pausedAt = start.addingTimeInterval(8 * 60)
        let cp = checkpoint(type: .work, startedAt: start, pausedAt: pausedAt)

        // Even a very long time later, elapsed stays frozen at 8 minutes, so
        // the session remains resumable with 17 minutes remaining.
        let outcome = CheckpointReconciler.reconcile(checkpoint: cp, now: start.addingTimeInterval(10 * 60 * 60))
        #expect(outcome == .resumable(remaining: 17 * 60, completedWorkSessions: 0, config: makeConfig()))
    }
}
