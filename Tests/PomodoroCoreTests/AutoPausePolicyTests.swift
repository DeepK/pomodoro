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

    @Test func autoFlagPlusActiveResumesAndClearsFlag() {
        var policy = AutoPausePolicy()
        _ = policy.systemBecameInactive(runStatus: .running) // now auto-paused
        let action = policy.systemBecameActive(runStatus: .paused)
        #expect(action == .resume)
        #expect(!policy.isAutoPaused)
    }

    @Test func manualPausePlusActiveDoesNotResume() {
        // No prior inactive event: the pause was the user's, so the flag is
        // never set and an active event must not resume.
        var policy = AutoPausePolicy()
        let action = policy.systemBecameActive(runStatus: .paused)
        #expect(action == .none)
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

    @Test func manualActionClearsFlagSoNoAutoResume() {
        var policy = AutoPausePolicy()
        _ = policy.systemBecameInactive(runStatus: .running) // auto-paused
        policy.userDidActManually()                          // user touched it
        #expect(!policy.isAutoPaused)
        let action = policy.systemBecameActive(runStatus: .paused)
        #expect(action == .none)
    }

    @Test func inactiveWhileIdleOrPausedIsNoOp() {
        var policy = AutoPausePolicy()
        #expect(policy.systemBecameInactive(runStatus: .idle) == .none)
        #expect(policy.systemBecameInactive(runStatus: .paused) == .none)
        #expect(!policy.isAutoPaused)
    }

    @Test func activeWhenNotPausedClearsFlagWithoutResuming() {
        // Edge: auto-paused, but the user already resumed via the manual path
        // is covered elsewhere; here the engine reports running at active time
        // (e.g. state raced) — clear the flag, do not emit a resume.
        var policy = AutoPausePolicy()
        _ = policy.systemBecameInactive(runStatus: .running)
        let action = policy.systemBecameActive(runStatus: .running)
        #expect(action == .none)
        #expect(!policy.isAutoPaused)
    }
}
