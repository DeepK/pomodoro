import Testing
import Foundation
@testable import PomodoroCore

// See TimerEngineTests for why these use swift-testing (`import Testing`)
// rather than XCTest in this Command Line Tools-only environment.

@Suite struct CheckpointStoreTests {
    /// Creates a unique temp file URL for an isolated store per test.
    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckpointStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("inflight.json")
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func makeConfig() -> TimerConfig {
        TimerConfig(
            workDuration: 25 * 60,
            shortBreakDuration: 5 * 60,
            longBreakDuration: 15 * 60,
            cyclesBeforeLongBreak: 4
        )
    }

    private func makeCheckpoint() -> SessionCheckpoint {
        SessionCheckpoint(
            sessionType: .work,
            startedAt: date("2026-09-14T10:00:00Z"),
            accumulatedPaused: 42,
            pausedAt: nil,
            completedWorkSessions: 2,
            config: makeConfig()
        )
    }

    @Test func absentCheckpointLoadsAsNil() {
        let store = CheckpointStore(fileURL: makeTempFileURL())
        #expect(store.load() == nil)
    }

    @Test func saveLoadRoundTripAcrossInstances() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = CheckpointStore(fileURL: url)
        let checkpoint = makeCheckpoint()
        try store.save(checkpoint)

        // A fresh instance reading the same file must see the saved checkpoint.
        let reopened = CheckpointStore(fileURL: url)
        #expect(reopened.load() == checkpoint)
    }

    @Test func saveOverwritesPreviousCheckpoint() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = CheckpointStore(fileURL: url)
        try store.save(makeCheckpoint())

        let paused = SessionCheckpoint(
            sessionType: .work,
            startedAt: date("2026-09-14T11:00:00Z"),
            accumulatedPaused: 0,
            pausedAt: date("2026-09-14T11:10:00Z"),
            completedWorkSessions: 3,
            config: makeConfig()
        )
        try store.save(paused)

        #expect(store.load() == paused)
    }

    @Test func clearRemovesCheckpoint() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = CheckpointStore(fileURL: url)
        try store.save(makeCheckpoint())
        #expect(store.load() != nil)

        store.clear()
        #expect(store.load() == nil)
    }

    @Test func clearOnAbsentFileIsANoOp() {
        let store = CheckpointStore(fileURL: makeTempFileURL())
        store.clear() // must not throw/crash
        #expect(store.load() == nil)
    }

    @Test func corruptCheckpointLoadsAsNilAndIsDeleted() throws {
        let url = makeTempFileURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Seed the checkpoint path with undecodable garbage.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("this is not valid json".utf8).write(to: url)

        let store = CheckpointStore(fileURL: url)

        // Corrupt data is treated as absent (nil), never a crash.
        #expect(store.load() == nil)

        // The corrupt file was deleted so it cannot wedge future launches.
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
