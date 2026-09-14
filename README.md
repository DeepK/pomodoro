# Pomodoro

A SwiftUI menu-bar Pomodoro timer for macOS 13+. It lives in the menu bar,
counts down work and break sessions, and keeps a local history of completed
work sessions with a simple bar-chart report.

## Features

- Configurable durations: work, short break, and long break, plus the number
  of work cycles before a long break.
- Session controls: start, pause, resume, skip, and reset.
- Menu-bar countdown: shows a live `mm:ss` countdown and the current phase
  (Work / Short Break / Long Break) while a session is active.
- Reports: a Swift Charts bar chart of completed work sessions, with a
  14-day (daily) or 8-week (weekly) view.
- Local session log persisted as a JSON array on disk.

## Requirements

- macOS 13 (Ventura) or later.
- Swift toolchain via the Xcode Command Line Tools (`xcode-select --install`),
  or full Xcode.

## Build & Run

From the repository root:

```sh
swift build            # compile
swift test             # run PomodoroCore unit tests
swift run Pomodoro      # build and launch the menu-bar app
```

The app appears in the macOS menu bar (there is no dock icon or main window);
click the menu-bar item to open the timer/reports popover, and use the popover
footer to open Settings or quit.

You can also open the package directly in Xcode:

```sh
xed .                  # or: File > Open... and select Package.swift
```

Then select the `Pomodoro` scheme and run.

> Note: on a Command Line Tools-only host, plain `swift build` may fail at
> XCBuild initialization with an "Unknown error parsing property list"
> toolchain error. If so, build with the native build system:
> `swift build --build-system native`.

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
