import Foundation
import Combine

/// Drives the pure ``TimerEngine`` forward in real time.
///
/// `TimerEngine` deliberately owns no real timer — it advances only when its
/// `tick(_:)` is called. This driver supplies those ticks on the main run loop
/// while a session is running. Depending on the ``TimerDriving`` abstraction
/// (Dependency Inversion) lets the view model be unit-tested with a fake
/// driver instead of a wall clock.
protocol TimerDriving: AnyObject {
    /// Invoked once per interval while the driver is running.
    var onTick: (() -> Void)? { get set }
    /// Begins delivering ticks. Idempotent.
    func start()
    /// Stops delivering ticks. Idempotent.
    func stop()
}

/// Wall-clock ``TimerDriving`` backed by a Combine `Timer.publish`.
///
/// Ticks are delivered on the main run loop in `.common` mode so the countdown
/// keeps updating while the menu-bar popover is open and tracking input.
final class TimerDriver: TimerDriving {
    private let interval: TimeInterval
    private var cancellable: AnyCancellable?

    var onTick: (() -> Void)?

    init(interval: TimeInterval = 1) {
        self.interval = interval
    }

    func start() {
        stop()
        cancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.onTick?() }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }
}
