import SwiftUI
import AppKit
import PomodoroCore

/// Content shown in the menu-bar popover (window style).
///
/// A segmented control switches between the live timer and the reports chart.
/// Settings are shown in-place inside the popover (toggled by the footer
/// button, dismissed by a back button): the dedicated `Settings` scene's
/// `showSettingsWindow:` action is a no-op for a non-bundled menu-bar
/// executable, so presenting settings here is reliable and needs no window
/// management. This view only renders state and forwards user intents to the
/// view model.
///
/// See the property-wrapper note in `PomodoroApp.swift` for why the wrappers
/// are declared in desugared form here.
struct MenuContentView: View {
    private var _viewModel: ObservedObject<PomodoroViewModel>
    private var viewModel: PomodoroViewModel { _viewModel.wrappedValue }

    private enum Tab: String, CaseIterable, Identifiable {
        case timer = "Timer"
        case reports = "Reports"
        var id: String { rawValue }
    }

    // Desugared `@State private var tab: Tab = .timer`.
    private var _tab = State<Tab>(initialValue: .timer)
    private var tab: Tab { _tab.wrappedValue }

    // Desugared `@State private var showingSettings = false`. Toggles the
    // popover between the main content and the embedded settings pane.
    private var _showingSettings = State<Bool>(initialValue: false)
    private var showingSettings: Bool { _showingSettings.wrappedValue }

    init(viewModel: PomodoroViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        if showingSettings {
            settingsPane
        } else {
            mainPane
        }
    }

    /// The default popover: section picker (timer/reports) plus the footer.
    private var mainPane: some View {
        VStack(spacing: 12) {
            Picker("View", selection: _tab.projectedValue) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Section")

            switch tab {
            case .timer:
                TimerControlsView(viewModel: viewModel)
            case .reports:
                ReportsView(viewModel: viewModel)
            }

            Divider()
            footer
        }
        .padding()
        .frame(width: 300)
    }

    /// Settings shown in-place inside the popover, with a back button that
    /// returns to `mainPane`. Reuses ``SettingsView`` (and thus the view
    /// model's `persistSettings` flow) unchanged.
    private var settingsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    _showingSettings.wrappedValue = false
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Back to timer")

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                // Invisible mirror of the back button so the title stays
                // centred without overlapping the leading control.
                Label("Back", systemImage: "chevron.backward")
                    .labelStyle(.iconOnly)
                    .hidden()
                    .accessibilityHidden(true)
            }
            .padding([.horizontal, .top])

            SettingsView(viewModel: viewModel)
        }
        .frame(width: 340)
    }

    private var footer: some View {
        HStack {
            Button {
                _showingSettings.wrappedValue = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityLabel("Open settings")

            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .accessibilityLabel("Quit Pomodoro")
        }
        .buttonStyle(.borderless)
    }
}

/// The live timer face: phase, big countdown, cycle progress, and controls.
private struct TimerControlsView: View {
    private var _viewModel: ObservedObject<PomodoroViewModel>
    private var viewModel: PomodoroViewModel { _viewModel.wrappedValue }

    init(viewModel: PomodoroViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 12) {
            phaseHeader
            countdown
            cycleProgress
            controls
        }
    }

    @ViewBuilder private var phaseHeader: some View {
        switch viewModel.snapshot.phase {
        case .idle:
            Label("Ready", systemImage: "timer")
                .font(.headline)
                .foregroundStyle(.secondary)
        case .active(let type):
            Label(type.displayName, systemImage: type.symbolName)
                .font(.headline)
                .foregroundStyle(type.tint)
                .accessibilityLabel("Current phase: \(type.displayName)")
        }
    }

    private var countdown: some View {
        Text(formatCountdown(viewModel.snapshot.remaining))
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityLabel("Time remaining")
            .accessibilityValue(formatCountdown(viewModel.snapshot.remaining))
    }

    @ViewBuilder private var cycleProgress: some View {
        if !viewModel.isIdle {
            Text("Cycle \(viewModel.cyclePosition)/\(viewModel.cadence)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "Cycle \(viewModel.cyclePosition) of \(viewModel.cadence) before long break"
                )
        } else {
            Text("\(viewModel.cadence) work sessions per long break")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if viewModel.isIdle {
                Button {
                    viewModel.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .accessibilityLabel("Start work session")
            } else {
                Button {
                    viewModel.togglePauseResume()
                } label: {
                    if viewModel.isRunning {
                        Label("Pause", systemImage: "pause.fill")
                    } else {
                        Label("Resume", systemImage: "play.fill")
                    }
                }
                .accessibilityLabel(viewModel.isRunning ? "Pause session" : "Resume session")

                Button {
                    viewModel.skip()
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                }
                .accessibilityLabel("Skip to next session")
            }

            Button {
                viewModel.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .disabled(viewModel.isIdle)
            .accessibilityLabel("Reset timer")
        }
        .buttonStyle(.bordered)
    }
}
