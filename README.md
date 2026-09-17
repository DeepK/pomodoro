# Pomodoro

A SwiftUI menu-bar Pomodoro timer for macOS 13+. It lives in the menu bar,
counts down work and break sessions, and keeps a local history of completed
work sessions with a simple bar-chart report.

## Features

- Configurable durations: work, short break, and long break, plus the number
  of work cycles before a long break.
- Session controls: start, pause, resume, skip, and reset.
- Auto-pauses when the screen locks or the Mac sleeps; resumes when you're back.
- Menu-bar countdown: shows a live `mm:ss` countdown and the current phase
  (Work / Short Break / Long Break) while a session is active.
- Reports: a Swift Charts bar chart of completed work sessions, with a
  14-day (daily) or 8-week (weekly) view.
- Local session log persisted as a JSON array on disk.

## Requirements

- macOS 13 (Ventura) or later.
- Swift toolchain via the Xcode Command Line Tools (`xcode-select --install`),
  or full Xcode.

## Installing on a new Mac

1. **Install the Apple Command Line Tools** (full Xcode also works but isn't
   required; on CLT-only machines the `Makefile` sets the required build flags
   automatically):

   ```sh
   xcode-select --install
   ```

2. **Clone the repository** (replace the placeholder with your fork/remote):

   ```sh
   git clone https://github.com/<you>/pomodoro.git && cd pomodoro
   ```

3. **Verify the build:**

   ```sh
   make test
   ```

4. **Run** with `make run` (this stays attached to the terminal):

   ```sh
   make run
   ```

   To run detached, build once and launch the binary in the background:

   ```sh
   make build
   .build/debug/Pomodoro &
   ```

Settings and session history are per-machine (stored in `UserDefaults` and
`~/Library/Application Support/Pomodoro/`), so your stats don't sync between Macs.

## Build & Run

The `make` targets shown above are the portable way to build, test, and run;
they auto-detect CLT-only vs full-Xcode hosts. With full Xcode you can also use
the plain SwiftPM commands directly:

```sh
swift build            # compile
swift test             # run PomodoroCore unit tests
swift run Pomodoro      # build and launch the menu-bar app
```

### CLT-only machines

On a Command Line Tools-only host, the default `swiftbuild` build system fails
at XCBuild initialization and `swift test` cannot locate `Testing.framework`.
The `Makefile` handles this automatically (`--build-system native` plus `-F`
search paths for the CLT Frameworks directory), so just use `make`.

The app appears in the macOS menu bar (there is no dock icon or main window);
click the menu-bar item to open the timer/reports popover, and use the popover
footer to open Settings or quit.

You can also open the package in Xcode (`xed .`, or open `Package.swift`) and
run the `Pomodoro` scheme.

## Data storage

Completed work sessions are written to:

```
~/Library/Application Support/Pomodoro/sessions.json
```

The file is a pretty-printed JSON array of `{ completedAt, duration }`
entries (ISO-8601 timestamps, duration in seconds), created on first write.
User settings are persisted separately in `UserDefaults`.

## Project structure

```
Package.swift                     SwiftPM manifest (macOS 13; 2 products)
Sources/
  PomodoroCore/                   UI-agnostic library
    TimerEngine.swift             timer state machine, phases, snapshots
    SettingsStore.swift           PomodoroSettings + persistence seam
    SessionLog.swift              JSON-backed work-session log + aggregation
    Clock.swift                   injectable time source
  Pomodoro/                       executable (menu-bar app)
    PomodoroApp.swift             @main MenuBarExtra + Settings scene
    MenuContentView.swift         timer/reports popover
    SettingsView.swift            duration/cycle settings form
    ReportsView.swift             Swift Charts bar chart
    PomodoroViewModel.swift       @MainActor bridge to PomodoroCore
    TimerDriver.swift             per-second tick driver (protocol + Combine)
    Presentation.swift            UI-only formatting/display helpers
Tests/
  PomodoroCoreTests/              unit tests for the core library
```

The business logic lives entirely in `PomodoroCore`; the `Pomodoro`
executable is a thin SwiftUI layer on top of it.

## Roadmap / not yet implemented

- Session tags/labels.
- CSV export of the session log.
- Signed `.dmg` packaging for distribution.
- Auto-start the next session on completion.
