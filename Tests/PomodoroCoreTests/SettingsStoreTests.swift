import Testing
import Foundation
@testable import PomodoroCore

/// In-memory ``KeyValueStore`` fake so tests never touch real UserDefaults.
private final class InMemoryStore: KeyValueStore {
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? { storage[key] }

    func set(_ data: Data?, forKey key: String) {
        storage[key] = data
    }
}

@Suite struct SettingsStoreTests {
    @Test func defaultsWhenEmpty() {
        let store = SettingsStore(store: InMemoryStore())
        #expect(store.load() == .default)
    }

    @Test func defaultValuesAreCorrect() {
        let defaults = PomodoroSettings.default
        #expect(defaults.workDuration == 25 * 60)
        #expect(defaults.shortBreakDuration == 5 * 60)
        #expect(defaults.longBreakDuration == 15 * 60)
        #expect(defaults.cyclesBeforeLongBreak == 4)
    }

    @Test func roundTrip() throws {
        let store = SettingsStore(store: InMemoryStore())
        let custom = PomodoroSettings(
            workDuration: 50 * 60,
            shortBreakDuration: 10 * 60,
            longBreakDuration: 30 * 60,
            cyclesBeforeLongBreak: 3
        )
        try store.save(custom)
        #expect(store.load() == custom)
    }

    @Test func corruptDataFallsBackToDefault() {
        let backing = InMemoryStore()
        backing.set(Data("not json".utf8), forKey: "com.pomodoro.settings")
        let store = SettingsStore(store: backing)
        #expect(store.load() == .default)
    }

    @Test func timerConfigProjection() {
        let config = PomodoroSettings.default.timerConfig
        #expect(config.workDuration == 25 * 60)
        #expect(config.cyclesBeforeLongBreak == 4)
    }
}
