import Foundation

/// A single completed WORK session.
public struct WorkSession: Codable, Equatable, Sendable {
    /// When the session completed.
    public let completedAt: Date
    /// How long the session ran, in seconds.
    public let duration: TimeInterval

    public init(completedAt: Date, duration: TimeInterval) {
        self.completedAt = completedAt
        self.duration = duration
    }
}

/// One day's completed-session count, used by aggregation queries.
public struct DayCount: Equatable, Sendable {
    /// Start-of-day (in the query's calendar) for the bucket.
    public let date: Date
    /// Number of work sessions completed on that day.
    public let count: Int

    public init(date: Date, count: Int) {
        self.date = date
        self.count = count
    }
}

/// Append-only log of completed work sessions, persisted as a JSON array.
///
/// The file location is injectable (Dependency Inversion) so tests write to a
/// temporary directory; production defaults to
/// `~/Library/Application Support/Pomodoro/sessions.json`.
///
/// Single responsibility: durable storage + read-back/aggregation of work
/// sessions. It does not know about the timer or settings.
public final class SessionLog {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Default on-disk location under Application Support.
    ///
    /// Falls back to a temporary directory if Application Support cannot be
    /// resolved (should not happen on macOS, but keeps the API non-throwing).
    public static func defaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Pomodoro", isDirectory: true)
            .appendingPathComponent("sessions.json", isDirectory: false)
    }

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? SessionLog.defaultFileURL(fileManager: fileManager)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Appends a completed work session to the log, creating the file (and
    /// its parent directory) if necessary.
    public func append(_ session: WorkSession) throws {
        var sessions = try allSessions()
        sessions.append(session)
        try write(sessions)
    }

    /// Returns all logged sessions in insertion order. An absent file yields
    /// an empty array (not an error).
    ///
    /// If the file exists but cannot be decoded (corruption/truncation), the
    /// bad file is moved aside (see ``quarantineCorruptFile()``) and an empty
    /// array is returned, so a single corrupt write does not make every future
    /// ``append(_:)`` throw forever — new sessions are recorded to a fresh log.
    public func allSessions() throws -> [WorkSession] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        do {
            return try decoder.decode([WorkSession].self, from: data)
        } catch is DecodingError {
            try quarantineCorruptFile()
            return []
        }
    }

    /// Number of completed work sessions per day for the last `lastNDays`
    /// days, inclusive of today, ordered oldest -> newest.
    ///
    /// Days with no sessions are included with a count of zero, so callers
    /// (e.g. a chart) get a contiguous, gap-free series.
    ///
    /// - Parameters:
    ///   - lastNDays: Number of days in the window (>= 1). Values < 1 yield [].
    ///   - now: Reference "current" instant; injected for deterministic tests.
    ///   - calendar: Calendar used for day bucketing (defaults to `.current`).
    public func sessionsPerDay(
        lastNDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> [DayCount] {
        guard lastNDays >= 1 else { return [] }

        let sessions = try allSessions()

        // Bucket sessions by their start-of-day.
        var countsByDay: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.completedAt)
            countsByDay[day, default: 0] += 1
        }

        // Emit one entry per day in the window, oldest first, zero-filled.
        let today = calendar.startOfDay(for: now)
        var result: [DayCount] = []
        result.reserveCapacity(lastNDays)
        for offset in stride(from: lastNDays - 1, through: 0, by: -1) {
            guard let day = calendar.date(
                byAdding: .day,
                value: -offset,
                to: today
            ) else { continue }
            result.append(DayCount(date: day, count: countsByDay[day] ?? 0))
        }
        return result
    }

    // MARK: - Private

    /// Moves a corrupt log file aside as `sessions.json.corrupt-<timestamp>`
    /// so it is preserved for manual recovery while freeing the canonical path
    /// for a fresh log. Any stale quarantine target at the same name is
    /// removed first so the move cannot fail on a collision.
    private func quarantineCorruptFile() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let corruptURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(
                "\(fileURL.lastPathComponent).corrupt-\(timestamp)",
                isDirectory: false
            )
        if fileManager.fileExists(atPath: corruptURL.path) {
            try fileManager.removeItem(at: corruptURL)
        }
        try fileManager.moveItem(at: fileURL, to: corruptURL)
    }

    private func write(_ sessions: [WorkSession]) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }
}
