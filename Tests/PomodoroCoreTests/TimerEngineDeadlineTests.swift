import Testing
import Foundation
@testable import PomodoroCore

// See TimerEngineTests for why these use swift-testing (`import Testing`).
//
// These tests cover the wall-clock, deadline-based timing added for crash
// recovery: remaining time is derived from the injected clock, so it stays
// correct even when ticks are missed (e.g. system sleep). They complement the
// tick-driven behaviour verified in TimerEngineTests.
@Suite struct TimerEngineDeadlineTests {
    private func makeConfig() -> TimerConfig {
        TimerConfig(
            workDuration: 4,
            shortBreakDuration: 1,
            longBreakDuration: 2,
            cyclesBeforeLongBreak: 4
        )
    }

    @Test func remainingDerivesFromClockWithoutTicks() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1000))
        let engine = TimerEngine(config: makeConfig(), clock: clock)
        engine.start()
        #expect(engine.snapshot.remaining == 4)

        // Advance the wall clock WITHOUT ticking: remaining tracks real time.
        clock.advance(by: 3)
        #expect(engine.snapshot.remaining == 1)
    }

    @Test func pausedWallClockTimeIsExcludedFromRemaining() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1000))
        let engine = TimerEngine(config: makeConfig(), clock: clock)
        engine.start()

        clock.advance(by: 1)          // 1s of real work elapsed -> 3 remain
        engine.pause()
        clock.advance(by: 100)        // long pause: must not consume the session
        #expect(engine.snapshot.remaining == 3)

        engine.resume()
        clock.advance(by: 1)          // 1 more second of work -> 2 remain
        #expect(engine.snapshot.remaining == 2)
    }

    @Test func missedTicksDuringSleepStillCompleteOnNextTick() {
        // Simulates system sleep: the clock jumps far past the work duration
        // while no ticks fire. The next tick must observe completion (the
        // drift-under-sleep fix) rather than only crediting a single second.
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1000))
        let engine = TimerEngine(config: makeConfig(), clock: clock)
        var completions: [SessionType] = []
        engine.onSessionComplete = { type, _ in completions.append(type) }

        engine.start()
        clock.advance(by: 3600) // asleep for an hour
        engine.tick(1)          // first tick after waking

        #expect(completions == [.work])
        #expect(engine.snapshot.phase == .active(.shortBreak))
    }

    @Test func makeCheckpointReturnsNilWhenIdle() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        #expect(engine.makeCheckpoint() == nil)
    }

    @Test func checkpointCapturesRunningSession() {
        let start = Date(timeIntervalSince1970: 1000)
        let clock = MutableClock(now: start)
        let engine = TimerEngine(config: makeConfig(), clock: clock)
        engine.start()
        clock.advance(by: 1)

        let checkpoint = engine.makeCheckpoint()
        #expect(checkpoint?.sessionType == .work)
        #expect(checkpoint?.startedAt == start)
        #expect(checkpoint?.accumulatedPaused == 0)
        #expect(checkpoint?.pausedAt == nil)
        #expect(checkpoint?.completedWorkSessions == 0)
    }

    @Test func checkpointCapturesOpenPause() {
        let start = Date(timeIntervalSince1970: 1000)
        let clock = MutableClock(now: start)
        let engine = TimerEngine(config: makeConfig(), clock: clock)
        engine.start()
        clock.advance(by: 1)
        engine.pause()

        let checkpoint = engine.makeCheckpoint()
        #expect(checkpoint?.pausedAt == clock.now)
        #expect(checkpoint?.accumulatedPaused == 0)
    }

    @Test func restoreResumesRemainingFromCheckpoint() {
        // A checkpoint 10m into a 25m work session, relaunched 5m later.
        let start = Date(timeIntervalSince1970: 1000)
        let config = TimerConfig(
            workDuration: 25 * 60,
            shortBreakDuration: 5 * 60,
            longBreakDuration: 15 * 60,
            cyclesBeforeLongBreak: 4
        )
        let checkpoint = SessionCheckpoint(
            sessionType: .work,
            startedAt: start,
            accumulatedPaused: 0,
            pausedAt: nil,
            completedWorkSessions: 2,
            config: config
        )

        let now = start.addingTimeInterval(15 * 60) // 15m of real elapsed
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock(now: now))
        engine.restore(from: checkpoint)

        #expect(engine.snapshot.phase == .active(.work))
        #expect(engine.snapshot.runState == .running)
        #expect(engine.snapshot.remaining == 10 * 60) // 25m - 15m elapsed
        #expect(engine.snapshot.completedWorkSessions == 2)
        #expect(engine.config == config) // adopted the checkpoint's config
    }

    @Test func checkpointRestoreRoundTripPreservesRemaining() {
        let start = Date(timeIntervalSince1970: 1000)
        let clock = MutableClock(now: start)
        let source = TimerEngine(config: makeConfig(), clock: clock)
        source.start()
        clock.advance(by: 1) // 1s elapsed -> 3 remain

        let checkpoint = try! #require(source.makeCheckpoint())

        // Restore into a fresh engine sharing the same clock instant.
        let restored = TimerEngine(config: makeConfig(), clock: clock)
        restored.restore(from: checkpoint)
        #expect(restored.snapshot.remaining == source.snapshot.remaining)
    }
}
