import SwiftUI
import PomodoroCore

// NOTE ON PROPERTY WRAPPERS
// On this host (Command Line Tools only, no Xcode.app, macOS 26 beta SDK) the
// SwiftUI property wrappers `@State`, `@StateObject`, `@ObservedObject`, and
// `@Binding` are implemented as macros backed by the `SwiftUIMacros` compiler
// plugin, which ships only with full Xcode and is not present here. To keep
// `swift build` green, this UI declares the wrappers' backing storage directly
// (e.g. `State<T>(initialValue:)`, `ObservedObject(wrappedValue:)`) and reads
// `.wrappedValue` / `.projectedValue` explicitly. This is exactly what the
// `@State`/`@StateObject`/`@ObservedObject` sugar expands to, so on a machine
// with full Xcode the attribute form can be restored verbatim with no
// behavioural change.

/// Menu-bar Pomodoro app.
///
/// The previous stage's CLI stub is replaced here with a `MenuBarExtra` scene
/// (macOS 13+). All timing, persistence, and aggregation logic lives in
/// `PomodoroCore`; ``PomodoroViewModel`` is the only bridge between that core
/// and these views. Settings are presented inside the popover (see
/// ``MenuContentView``) rather than via a `Settings` scene, whose
/// `showSettingsWindow:` action is unreliable for a non-bundled menu-bar
/// executable.
@main
struct PomodoroApp: App {
    // Desugared `@StateObject private var viewModel = PomodoroViewModel()`.
    private var _viewModel = StateObject(wrappedValue: PomodoroViewModel())
    private var viewModel: PomodoroViewModel { _viewModel.wrappedValue }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu-bar label: a timer symbol, plus the live `mm:ss` countdown and a
/// phase glyph while a session is active.
private struct MenuBarLabel: View {
    // Desugared `@ObservedObject var viewModel: PomodoroViewModel`.
    private var _viewModel: ObservedObject<PomodoroViewModel>
    private var viewModel: PomodoroViewModel { _viewModel.wrappedValue }

    init(viewModel: PomodoroViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        switch viewModel.snapshot.phase {
        case .idle:
            Image(systemName: "timer")
                .accessibilityLabel("Pomodoro timer, idle")
        case .active(let type):
            HStack(spacing: 4) {
                Image(systemName: type.symbolName)
                Text(formatCountdown(viewModel.snapshot.remaining))
                    .monospacedDigit()
            }
            .accessibilityLabel("\(type.displayName), \(formatCountdown(viewModel.snapshot.remaining)) remaining")
        }
    }
}
