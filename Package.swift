// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PomodoroCore", targets: ["PomodoroCore"]),
        .executable(name: "Pomodoro", targets: ["Pomodoro"]),
    ],
    targets: [
        // UI-agnostic core: timer state machine, settings, and session logging.
        .target(name: "PomodoroCore"),
        // Executable entry point. A later stage replaces this stub with the
        // MenuBarExtra + Swift Charts UI built on top of PomodoroCore.
        .executableTarget(
            name: "Pomodoro",
            dependencies: ["PomodoroCore"]
        ),
        .testTarget(
            name: "PomodoroCoreTests",
            dependencies: ["PomodoroCore"]
        ),
    ]
)
