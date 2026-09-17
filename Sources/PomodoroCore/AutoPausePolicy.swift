import Foundation

/// Pure decision logic for auto-pausing the timer while the Mac is "away"
/// (asleep, display off, screen locked, or running a screensaver) and
/// auto-resuming when it comes back.
///
/// This type is deliberately free of any AppKit / notification dependency: it
/// only tracks the single bit of policy state — whether the *current* pause was
/// initiated by the system (auto) rather than the user — and maps
/// system/user events to an ``Action`` for the view model to perform. Keeping
/// it here (rather than in the UI target) lets it be unit-tested from the
/// CLT-only test target, which cannot import the app target. The view model
/// owns the AppKit ``SystemActivityMonitor`` and forwards its events here,
/// mirroring the codebase's Dependency-Inversion style (`Clock`,
/// `TimerDriving`): policy is pure, side effects live at the edge.
///
/// State-machine summary (the `runStatus` argument is the engine's current
/// run state at the moment of the event):
///  - system inactive + `running` + not already auto-paused -> ``Action/pause``
///    and set the auto flag; any other inactive event is a no-op (idempotent,
///    so repeated sleep/lock notifications never stack).
///  - system active + auto flag set + `paused` -> ``Action/resume`` and clear
///    the flag; if the flag is not set (e.g. the user paused manually) the
///    active event is a no-op, so a manual pause is never auto-resumed.
///  - any manual user action (start/pause/resume/reset/skip) clears the flag,
///    so a session the user touched while away is no longer treated as
///    system-paused.
public struct AutoPausePolicy: Equatable, Sendable {
    /// The engine run state relevant to the policy's decisions.
    public enum RunStatus: Equatable, Sendable {
        case running
        case paused
        case idle
    }

    /// The action the view model should perform in response to an event.
    public enum Action: Equatable, Sendable {
        case none
        case pause
        case resume
    }

    /// Whether the current pause was initiated by the system (i.e. is eligible
    /// for auto-resume). Cleared on resume and on any manual user action.
    public private(set) var isAutoPaused: Bool

    public init(isAutoPaused: Bool = false) {
        self.isAutoPaused = isAutoPaused
    }

    /// The Mac became inactive (sleep, display sleep, screen lock, screensaver
    /// start). Pauses a running session exactly once and remembers the pause
    /// was automatic; every other case is a no-op so stacked inactive events
    /// stay idempotent.
    public mutating func systemBecameInactive(runStatus: RunStatus) -> Action {
        guard !isAutoPaused, runStatus == .running else { return .none }
        isAutoPaused = true
        return .pause
    }

    /// The Mac became active (wake, screens wake, unlock, screensaver stop).
    /// Resumes only a session that this policy auto-paused and is still paused,
    /// then clears the flag. A user's manual pause (flag not set) is left alone.
    public mutating func systemBecameActive(runStatus: RunStatus) -> Action {
        guard isAutoPaused else { return .none }
        isAutoPaused = false
        return runStatus == .paused ? .resume : .none
    }

    /// The user manually started/paused/resumed/reset/skipped a session.
    /// Clears the auto flag so the touched session is no longer auto-resumed.
    public mutating func userDidActManually() {
        isAutoPaused = false
    }
}
