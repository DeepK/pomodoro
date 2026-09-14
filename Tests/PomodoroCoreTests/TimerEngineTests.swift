import Testing
import Foundation
@testable import PomodoroCore

// NOTE: Tests use swift-testing (`import Testing`) rather than XCTest. The
// full XCTest framework ships only with Xcode.app, which is not installed in
// this environment (Command Line Tools only), so XCTest cannot be compiled
// here. swift-testing is Apple's first-party, toolchain-bundled test
// framework and provides equivalent coverage.

@Suite struct TimerEngineTests {
    /// Small, easy-to-reason-about config: 4s work, 1s short, 2s long, long
    /// break after every 4th work session.
    private func makeConfig() -> TimerConfig {
        TimerConfig(
            workDuration: 4,
            shortBreakDuration: 1,
            longBreakDuration: 2,
            cyclesBeforeLongBreak: 4
        )
    }

    /// Ticks a running session one second at a time.
    private func drain(_ engine: TimerEngine, seconds: Int) {
        for _ in 0..<seconds { engine.tick(1) }
    }

    @Test func startsIdle() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        #expect(engine.snapshot.phase == .idle)
        #expect(engine.snapshot.runState == nil)
        #expect(engine.snapshot.remaining == 0)
    }

    @Test func startBeginsRunningWork() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        engine.start()
        #expect(engine.snapshot.phase == .active(.work))
        #expect(engine.snapshot.runState == .running)
        #expect(engine.snapshot.remaining == 4)
    }

    @Test func tickOnlyCountsWhileRunning() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        engine.start()
        engine.pause()
        engine.tick(1)
        #expect(engine.snapshot.remaining == 4) // paused: unchanged
        #expect(engine.snapshot.runState == .paused)
        engine.resume()
        engine.tick(1)
        #expect(engine.snapshot.remaining == 3)
    }

    @Test func workCompletionEmitsAndTransitionsToShortBreak() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1000))
        let engine = TimerEngine(config: makeConfig(), clock: clock)

        var completions: [(SessionType, Date)] = []
        engine.onSessionComplete = { completions.append(($0, $1)) }

        engine.start()
        drain(engine, seconds: 4)

        #expect(completions.count == 1)
        #expect(completions.first?.0 == .work)
        #expect(completions.first?.1 == clock.now) // timestamp from injected clock
        #expect(engine.snapshot.phase == .active(.shortBreak))
        #expect(engine.snapshot.runState == .running)
        #expect(engine.snapshot.remaining == 1)
        #expect(engine.snapshot.completedWorkSessions == 1)
    }

    @Test func fullCycleReachesLongBreakAfterConfiguredWorkSessions() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        var completed: [SessionType] = []
        engine.onSessionComplete = { type, _ in completed.append(type) }

        engine.start()

        // work(4)->short(1)->work(4)->short(1)->work(4)->short(1)->work(4)
        drain(engine, seconds: 4) // work #1 -> short
        drain(engine, seconds: 1) // short   -> work
        drain(engine, seconds: 4) // work #2 -> short
        drain(engine, seconds: 1) // short   -> work
        drain(engine, seconds: 4) // work #3 -> short
        drain(engine, seconds: 1) // short   -> work
        drain(engine, seconds: 4) // work #4 -> LONG break

        #expect(engine.snapshot.phase == .active(.longBreak))
        #expect(engine.snapshot.remaining == 2)
        #expect(engine.snapshot.completedWorkSessions == 4)
        #expect(completed == [.work, .shortBreak, .work, .shortBreak, .work, .shortBreak, .work])

        // Completing the long break returns to work.
        drain(engine, seconds: 2)
        #expect(engine.snapshot.phase == .active(.work))
        #expect(completed.last == .longBreak)
    }

    @Test func skipAdvancesWithoutEmittingCompletion() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        var completions = 0
        engine.onSessionComplete = { _, _ in completions += 1 }

        engine.start()
        engine.skip() // work -> short break, no completion counted

        #expect(completions == 0)
        #expect(engine.snapshot.phase == .active(.shortBreak))
        #expect(engine.snapshot.completedWorkSessions == 0)
        #expect(engine.snapshot.remaining == 1)
    }

    @Test func resetReturnsToIdleAndClearsCounter() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        engine.start()
        drain(engine, seconds: 4) // one work done
        #expect(engine.snapshot.completedWorkSessions == 1)

        engine.reset()
        #expect(engine.snapshot.phase == .idle)
        #expect(engine.snapshot.runState == nil)
        #expect(engine.snapshot.remaining == 0)
        #expect(engine.snapshot.completedWorkSessions == 0)
    }

    @Test func pauseResumeAreNoOpsWhenNotApplicable() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        engine.resume() // idle -> no-op
        engine.pause()  // idle -> no-op
        #expect(engine.snapshot.phase == .idle)

        engine.start()
        engine.resume() // already running -> no-op
        #expect(engine.snapshot.runState == .running)
    }

    @Test func tickDoesNotOverrunIntoNextSession() {
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        engine.start()
        // A single oversized tick completes exactly one session and starts the
        // next fresh (no negative/leftover carry-over).
        engine.tick(100)
        #expect(engine.snapshot.phase == .active(.shortBreak))
        #expect(engine.snapshot.remaining == 1)
    }

    @Test func updateThenStartUsesNewDurations() {
        // Mirrors the view model's start()/reset() path: a config swapped in
        // between sessions must take effect on the next start. Guards the
        // CRITICAL fix where mid-session settings edits never reached a fresh
        // session.
        let engine = TimerEngine(config: makeConfig(), clock: MutableClock())
        engine.start()
        #expect(engine.snapshot.remaining == 4) // original work duration

        engine.reset()
        engine.update(config: TimerConfig(
            workDuration: 10,
            shortBreakDuration: 2,
            longBreakDuration: 3,
            cyclesBeforeLongBreak: 2
        ))
        engine.start()
        #expect(engine.snapshot.phase == .active(.work))
        #expect(engine.snapshot.remaining == 10) // new work duration applied
    }
}
