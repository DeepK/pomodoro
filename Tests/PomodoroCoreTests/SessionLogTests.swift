import Testing
import Foundation
@testable import PomodoroCore

@Suite struct SessionLogTests {
    // A fixed UTC calendar so day-bucketing is deterministic regardless of the
    // machine's locale/timezone.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Creates a unique temp file URL for an isolated log per test.
    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLogTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func emptyLogHasNoSessions() throws {
        let log = SessionLog(fileURL: makeTempFileURL())
        #expect(try log.allSessions() == [])
    }

    @Test func appendPersistsAcrossInstances() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let log = SessionLog(fileURL: url)
        let session = WorkSession(completedAt: date("2026-09-14T10:00:00Z"), duration: 1500)
        try log.append(session)

        // A fresh instance reading the same file must see the appended row.
        let reopened = SessionLog(fileURL: url)
        #expect(try reopened.allSessions() == [session])
    }

    @Test func appendPreservesOrder() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let log = SessionLog(fileURL: url)
        let a = WorkSession(completedAt: date("2026-09-14T09:00:00Z"), duration: 1500)
        let b = WorkSession(completedAt: date("2026-09-14T10:00:00Z"), duration: 1500)
        try log.append(a)
        try log.append(b)
        #expect(try log.allSessions() == [a, b])
    }

    @Test func sessionsPerDayZeroFillsWindow() throws {
        let log = SessionLog(fileURL: makeTempFileURL())
        let now = date("2026-09-14T12:00:00Z")

        let result = try log.sessionsPerDay(lastNDays: 3, now: now, calendar: utcCalendar)

        #expect(result.count == 3)
        #expect(result.map(\.count) == [0, 0, 0])
        #expect(result.first?.date == utcCalendar.startOfDay(for: date("2026-09-12T00:00:00Z")))
        #expect(result.last?.date == utcCalendar.startOfDay(for: now))
    }

    @Test func sessionsPerDayAggregatesAcrossDayBoundaries() throws {
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = SessionLog(fileURL: url)

        // Two on the 14th, one on the 13th, one on the 12th, and one OUTSIDE
        // the 3-day window (the 11th) which must be excluded.
        try log.append(WorkSession(completedAt: date("2026-09-14T08:00:00Z"), duration: 1500))
        try log.append(WorkSession(completedAt: date("2026-09-14T23:30:00Z"), duration: 1500))
        try log.append(WorkSession(completedAt: date("2026-09-13T13:00:00Z"), duration: 1500))
        try log.append(WorkSession(completedAt: date("2026-09-12T00:15:00Z"), duration: 1500))
        try log.append(WorkSession(completedAt: date("2026-09-11T22:00:00Z"), duration: 1500))

        let now = date("2026-09-14T12:00:00Z")
        let result = try log.sessionsPerDay(lastNDays: 3, now: now, calendar: utcCalendar)

        #expect(result.count == 3)
        // Sept 12 -> 1, Sept 13 -> 1, Sept 14 -> 2. Sept 11 excluded.
        #expect(result.map(\.count) == [1, 1, 2])
        #expect(result[0].date == utcCalendar.startOfDay(for: date("2026-09-12T00:00:00Z")))
        #expect(result[1].date == utcCalendar.startOfDay(for: date("2026-09-13T00:00:00Z")))
        #expect(result[2].date == utcCalendar.startOfDay(for: date("2026-09-14T00:00:00Z")))
    }

    @Test func sessionsPerDayInvalidWindowReturnsEmpty() throws {
        let log = SessionLog(fileURL: makeTempFileURL())
        #expect(try log.sessionsPerDay(lastNDays: 0, now: Date(), calendar: utcCalendar) == [])
    }

    @Test func engineCompletionCanBeLogged() throws {
        // Integration-ish: wire the engine's callback to the log for WORK only.
        let url = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let clock = MutableClock(now: date("2026-09-14T08:00:00Z"))
        let engine = TimerEngine(
            config: TimerConfig(workDuration: 2, shortBreakDuration: 1, longBreakDuration: 2, cyclesBeforeLongBreak: 4),
            clock: clock
        )
        let log = SessionLog(fileURL: url)
        engine.onSessionComplete = { type, when in
            guard type == .work else { return }
            try? log.append(WorkSession(completedAt: when, duration: 2))
        }

        engine.start()
        engine.tick(1)
        engine.tick(1) // completes work -> logs one session

        #expect(try log.allSessions().count == 1)
        #expect(try log.allSessions().first?.completedAt == clock.now)
    }

    @Test func corruptLogIsQuarantinedAndAppendSucceeds() throws {
        let url = makeTempFileURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Seed the log path with undecodable garbage.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("this is not valid json".utf8).write(to: url)

        let log = SessionLog(fileURL: url)
        let session = WorkSession(completedAt: date("2026-09-14T10:00:00Z"), duration: 1500)

        // Appending must succeed instead of throwing forever on the corruption.
        try log.append(session)

        // The fresh log holds only the newly appended session.
        #expect(try log.allSessions() == [session])

        // The corrupt file was moved aside (sessions.json.corrupt-<timestamp>).
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(siblings.contains { $0.hasPrefix("sessions.json.corrupt-") })
    }
}
