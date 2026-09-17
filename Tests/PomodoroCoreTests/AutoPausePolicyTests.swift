import Testing
@testable import PomodoroCore

// See TimerEngineTests for why these use swift-testing rather than XCTest.

@Suite struct AutoPausePolicyTests {
    @Test func runningPlusInactivePausesAndSetsFlag() {
        var policy = AutoPausePolicy()
        let action = policy.systemBecameInactive(runStatus: .running)
        #expect(action == .pause)
        #expect(policy.isAutoPaused)
    }

    @Test func activeAfterAutoPauseClearsFlagAndNeverResumes() {
        // Resuming is ALWAYS manual: an active event must not resume. It only
        // clears the away flag so the UI can drop the "Paused — away" cue; the
        // session stays paused until the user acts.
        var policy = AutoPausePolicy()
        _ = policy.systemBecameInactive(runStatus: .running) // now auto-paused
        policy.systemBecameActive()
        #expect(!policy.isAutoPaused)
    }

    @Test func manualPausePlusActiveKeepsFlagClear() {
        // No prior inactive event: the pause was the user's, so the flag is
        // never set and an active event changes nothing (still no auto-resume).
        var policy = AutoPausePolicy()
        policy.systemBecameActive()
        #expect(!policy.isAutoPaused)
    }

    @Test func doubleInactiveIsIdempotent() {
        var policy = AutoPausePolicy()
        let first = policy.systemBecameInactive(runStatus: .running)
        // A second inactive event (now the session is paused) must not stack.
        let second = policy.systemBecameInactive(runStatus: .paused)
        #expect(first == .pause)
        #expect(second == .none)
        #expect(policy.isAutoPaused)
    }

    @Test func manualActionClearsFlagAndActiveStaysNoOp() {
        var policy = AutoPausePolicy()
        _ = policy.systemBecameInactive(runStatus: .running) // auto-paused
        policy.userDidActManually()                          // user touched it
        #expect(!policy.isAutoPaused)
        // A later active event remains a no-op on state (still no resume).
        policy.systemBecameActive()
        #expect(!policy.isAutoPaused)
    }

    @Test func inactiveWhileIdleOrPausedIsNoOp() {
        var policy = AutoPausePolicy()
        #expect(policy.systemBecameInactive(runStatus: .idle) == .none)
        #expect(policy.systemBecameInactive(runStatus: .paused) == .none)
        #expect(!policy.isAutoPaused)
    }

    @Test func repeatedActiveIsIdempotentAndAlwaysClears() {
        // Active clears the away flag no matter how many times it fires, and
        // never produces a resume — there is no resume action any more.
        var policy = AutoPausePolicy()
        _ = policy.systemBecameInactive(runStatus: .running)
        policy.systemBecameActive()
        policy.systemBecameActive()
        #expect(!policy.isAutoPaused)
    }
}
