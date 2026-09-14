import SwiftUI
import PomodoroCore

/// UI-only presentation of core session/phase types.
///
/// These extensions live in the app target (not `PomodoroCore`) so the core
/// stays free of any SwiftUI/AppKit dependency (SRP): the core models state,
/// the UI decides how to render it.
extension SessionType {
    /// Human-readable label shown in the popover and menu bar.
    var displayName: String {
        switch self {
        case .work: return "Work"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    /// SF Symbol representing the session type.
    var symbolName: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "figure.walk"
        }
    }

    /// Accent colour used for the phase label and countdown.
    var tint: Color {
        switch self {
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }
}

extension Phase {
    /// Label for the current phase, including an idle placeholder.
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .active(let type): return type.displayName
        }
    }
}

/// Formats a seconds count as `mm:ss` for the countdown displays.
///
/// Values are clamped at zero so a slightly negative remaining time (possible
/// mid-tick) never renders as a negative clock.
func formatCountdown(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d", total / 60, total % 60)
}
