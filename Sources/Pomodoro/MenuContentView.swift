import SwiftUI
import AppKit
import PomodoroCore

/// Content shown in the menu-bar popover (window style).
///
/// A segmented control switches between the live timer and the reports chart.
/// Settings open in the dedicated `Settings` scene. This view only renders
/// state and forwards user intents to the view model.
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

    init(viewModel: PomodoroViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
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

    private var footer: some View {
        HStack {
            Button {
                openSettings()
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

    /// Opens the `Settings` scene. `SettingsLink` is macOS 14+, so we use the
    /// standard AppKit action that shows the settings window, then bring the
    /// app forward (it is a menu-bar accessory).
    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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
