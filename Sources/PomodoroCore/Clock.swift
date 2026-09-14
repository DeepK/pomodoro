import Foundation

/// Abstraction over the current wall-clock time.
///
/// Injecting a `Clock` (Dependency Inversion) keeps `TimerEngine` and
/// `SessionLog` free of a direct `Date()` / `Timer` dependency, so tests can
/// drive time deterministically instead of relying on the real clock.
public protocol Clock {
    /// The current instant, as observed by this clock.
    var now: Date { get }
}

/// Production `Clock` backed by the system wall clock.
public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }
}

/// Test/utility `Clock` whose `now` can be set explicitly and advanced.
///
/// Not used by production code, but lives here so both the library and its
/// tests can share a single, well-understood fake.
public final class MutableClock: Clock {
    public var now: Date

    public init(now: Date = Date()) {
        self.now = now
    }

    /// Advances the clock by `interval` seconds.
    public func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
