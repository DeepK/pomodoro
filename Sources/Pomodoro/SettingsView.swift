import SwiftUI
import PomodoroCore

/// Editable Pomodoro settings, shown in the `Settings` scene.
///
/// Durations are edited in minutes (the store keeps seconds). Every change is
/// persisted through the view model; while a session is active the new config
/// is stored but only applied on the next reset, so a note explains that.
///
/// See the property-wrapper note in `PomodoroApp.swift` for the desugared
/// `ObservedObject` declaration.
struct SettingsView: View {
    private var _viewModel: ObservedObject<PomodoroViewModel>
    private var viewModel: PomodoroViewModel { _viewModel.wrappedValue }

    init(viewModel: PomodoroViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section("Durations (minutes)") {
                Stepper(
                    "Work: \(minutes(\.workDuration))",
                    value: minutesBinding(\.workDuration, range: 1...120)
                )
                .accessibilityLabel("Work duration in minutes")

                Stepper(
                    "Short break: \(minutes(\.shortBreakDuration))",
                    value: minutesBinding(\.shortBreakDuration, range: 1...60)
                )
                .accessibilityLabel("Short break duration in minutes")

                Stepper(
                    "Long break: \(minutes(\.longBreakDuration))",
                    value: minutesBinding(\.longBreakDuration, range: 1...120)
                )
                .accessibilityLabel("Long break duration in minutes")
            }

            Section("Cadence") {
                Stepper(
                    "Work sessions before long break: \(viewModel.settings.cyclesBeforeLongBreak)",
                    value: cyclesBinding(range: 1...12)
                )
                .accessibilityLabel("Work sessions before a long break")
            }

            if !viewModel.isIdle {
                Section {
                    Label(
                        "A session is active. New durations apply after Reset.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .padding()
    }

    // MARK: - Bindings

    private func minutes(_ keyPath: KeyPath<PomodoroSettings, TimeInterval>) -> Int {
        Int(viewModel.settings[keyPath: keyPath] / 60)
    }

    /// Two-way binding that reads/writes a duration in minutes and persists.
    private func minutesBinding(
        _ keyPath: WritableKeyPath<PomodoroSettings, TimeInterval>,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { Int(viewModel.settings[keyPath: keyPath] / 60) },
            set: { newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                viewModel.settings[keyPath: keyPath] = TimeInterval(clamped * 60)
                viewModel.persistSettings()
            }
        )
    }

    private func cyclesBinding(range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { viewModel.settings.cyclesBeforeLongBreak },
            set: { newValue in
                viewModel.settings.cyclesBeforeLongBreak =
                    min(max(newValue, range.lowerBound), range.upperBound)
                viewModel.persistSettings()
            }
        )
    }
}
