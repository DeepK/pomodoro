import Foundation

/// User-configurable Pomodoro settings.
///
/// Durations are stored in seconds so they map directly onto
/// ``TimerConfig`` without further conversion.
public struct PomodoroSettings: Codable, Equatable, Sendable {
    /// Work session length, in seconds.
    public var workDuration: TimeInterval
    /// Short break length, in seconds.
    public var shortBreakDuration: TimeInterval
    /// Long break length, in seconds.
    public var longBreakDuration: TimeInterval
    /// Completed work sessions before a long break.
    public var cyclesBeforeLongBreak: Int

    public init(
        workDuration: TimeInterval,
        shortBreakDuration: TimeInterval,
        longBreakDuration: TimeInterval,
        cyclesBeforeLongBreak: Int
    ) {
        self.workDuration = workDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.cyclesBeforeLongBreak = cyclesBeforeLongBreak
    }

    /// Default settings: 25m work, 5m short break, 15m long break, 4 cycles.
    public static let `default` = PomodoroSettings(
        workDuration: 25 * 60,
        shortBreakDuration: 5 * 60,
        longBreakDuration: 15 * 60,
        cyclesBeforeLongBreak: 4
    )

    /// Projects these settings onto a ``TimerConfig``.
    public var timerConfig: TimerConfig {
        TimerConfig(
            workDuration: workDuration,
            shortBreakDuration: shortBreakDuration,
            longBreakDuration: longBreakDuration,
            cyclesBeforeLongBreak: cyclesBeforeLongBreak
        )
    }
}

/// Minimal key/value persistence seam.
///
/// Depending on this abstraction (rather than `UserDefaults` directly) lets
/// tests substitute an in-memory fake — Dependency Inversion in practice.
public protocol KeyValueStore {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// `UserDefaults` conformance for production use.
extension UserDefaults: KeyValueStore {
    public func set(_ data: Data?, forKey key: String) {
        // Explicit overload so the `Data?` protocol requirement is satisfied
        // unambiguously (UserDefaults' own `set` takes `Any?`).
        setValue(data, forKey: key)
    }
}

/// Loads and saves ``PomodoroSettings`` through a ``KeyValueStore``.
///
/// Single responsibility: (de)serialization + persistence of settings. It
/// knows nothing about timers or the UI.
public final class SettingsStore {
    private let store: KeyValueStore
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(store: KeyValueStore, key: String = "com.pomodoro.settings") {
        self.store = store
        self.key = key
    }

    /// Returns persisted settings, or ``PomodoroSettings/default`` when none
    /// are stored or the stored data cannot be decoded.
    public func load() -> PomodoroSettings {
        guard
            let data = store.data(forKey: key),
            let settings = try? decoder.decode(PomodoroSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    /// Persists `settings`. Throws only if encoding fails.
    public func save(_ settings: PomodoroSettings) throws {
        let data = try encoder.encode(settings)
        store.set(data, forKey: key)
    }
}
