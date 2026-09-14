import Foundation

/// Persists a single in-flight ``SessionCheckpoint`` as JSON.
///
/// The file location is injectable (Dependency Inversion) so tests write to a
/// temporary directory; production defaults to
/// `~/Library/Application Support/Pomodoro/inflight.json` — the same directory
/// as `sessions.json`. Writes are atomic, like ``SessionLog``.
///
/// Single responsibility: durable save/load/clear of the current checkpoint.
/// It knows nothing about the timer, settings, or the completed-session log —
/// in particular, checkpointing deliberately does not leak into ``SessionLog``.
///
/// Only one checkpoint is ever stored: ``save(_:)`` overwrites any previous
/// one, so the file always reflects the latest in-flight session (or is absent
/// once cleared).
public final class CheckpointStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Default on-disk location under Application Support, alongside
    /// `sessions.json`.
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
            .appendingPathComponent("inflight.json", isDirectory: false)
    }

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? CheckpointStore.defaultFileURL(fileManager: fileManager)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Persists `checkpoint`, overwriting any existing one and creating the
    /// parent directory if necessary. The write is atomic.
    public func save(_ checkpoint: SessionCheckpoint) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let data = try encoder.encode(checkpoint)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Returns the persisted checkpoint, or `nil` when none exists.
    ///
    /// A missing file is not an error. If the file exists but cannot be read or
    /// decoded (corruption/truncation from a crash mid-write), it is treated as
    /// absent: the bad file is deleted and `nil` is returned. Loading never
    /// throws and never crashes, so a corrupt checkpoint can never wedge
    /// launch.
    public func load() -> SessionCheckpoint? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard
            let data = try? Data(contentsOf: fileURL),
            !data.isEmpty,
            let checkpoint = try? decoder.decode(SessionCheckpoint.self, from: data)
        else {
            clear()
            return nil
        }
        return checkpoint
    }

    /// Removes any persisted checkpoint. Best-effort and non-throwing: a
    /// missing file (or a failure to delete) is ignored, since the goal is
    /// simply that no checkpoint remains.
    public func clear() {
        try? fileManager.removeItem(at: fileURL)
    }
}
