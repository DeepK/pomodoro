import PomodoroCore

/// Temporary command-line entry point.
///
/// This stub only proves the executable target links against `PomodoroCore`.
/// A later stage replaces it with the SwiftUI `MenuBarExtra` + Swift Charts
/// application built on top of the same core modules.
@main
struct PomodoroApp {
    static func main() {
        let settings = PomodoroSettings.default
        let engine = TimerEngine(config: settings.timerConfig, clock: SystemClock())
        // Touch the snapshot so the linker keeps the core symbols and to give
        // a minimal, human-readable signal that wiring works.
        let state = engine.snapshot
        print("Pomodoro core ready. Phase: \(state.phase), work: \(Int(settings.workDuration))s")
    }
}
