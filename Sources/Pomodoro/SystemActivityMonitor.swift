import Foundation
import AppKit

/// Observes system activity transitions that should pause/resume the timer.
///
/// The timer should freeze while the Mac is "away" — asleep, its display off,
/// the screen locked, or a screensaver running — because the wall-clock engine
/// otherwise counts that real time against the session (see ``TimerEngine``).
/// Depending on this abstraction (Dependency Inversion, mirroring
/// ``TimerDriving`` / `Clock`) lets ``PomodoroViewModel`` be exercised with a
/// fake monitor instead of real system notifications.
protocol SystemActivityMonitoring: AnyObject {
    /// Invoked (on the main queue) when the Mac becomes inactive: system sleep,
    /// display sleep, screen lock, or screensaver start.
    var onInactive: (() -> Void)? { get set }
    /// Invoked (on the main queue) when the Mac becomes active again: wake,
    /// screens wake, unlock, or screensaver stop.
    var onActive: (() -> Void)? { get set }
    /// Begins observing. Idempotent.
    func start()
    /// Stops observing and releases all registrations. Idempotent.
    func stop()
}

/// Real ``SystemActivityMonitoring`` backed by the system notification centers.
///
/// Sleep/wake and display-sleep/wake are posted on `NSWorkspace`'s notification
/// center; screen lock/unlock and screensaver start/stop are posted as
/// *distributed* notifications (`com.apple.screenIsLocked` etc.) on
/// `DistributedNotificationCenter`. Observers are registered on the main queue
/// and torn down on ``stop()`` / `deinit`, so callbacks are always delivered on
/// the main thread where the view model mutates UI state.
final class SystemActivityMonitor: SystemActivityMonitoring {
    var onInactive: (() -> Void)?
    var onActive: (() -> Void)?

    private let workspaceCenter: NotificationCenter
    private let distributedCenter: DistributedNotificationCenter
    private var tokens: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - workspaceCenter: `NSWorkspace`'s center (sleep/wake, screen sleep).
    ///   - distributedCenter: Center for lock/unlock and screensaver events.
    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedCenter: DistributedNotificationCenter = .default()
    ) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
    }

    func start() {
        guard tokens.isEmpty else { return }

        // Inactive: system sleep + display sleep (workspace center).
        addWorkspace(NSWorkspace.willSleepNotification, fire: { self.onInactive?() })
        addWorkspace(NSWorkspace.screensDidSleepNotification, fire: { self.onInactive?() })
        // Active: wake + screens wake (workspace center).
        addWorkspace(NSWorkspace.didWakeNotification, fire: { self.onActive?() })
        addWorkspace(NSWorkspace.screensDidWakeNotification, fire: { self.onActive?() })

        // Inactive: screen lock + screensaver start (distributed center).
        addDistributed("com.apple.screenIsLocked", fire: { self.onInactive?() })
        addDistributed("com.apple.screensaver.didstart", fire: { self.onInactive?() })
        // Active: unlock + screensaver stop (distributed center).
        addDistributed("com.apple.screenIsUnlocked", fire: { self.onActive?() })
        addDistributed("com.apple.screensaver.didstop", fire: { self.onActive?() })
    }

    func stop() {
        for token in tokens {
            workspaceCenter.removeObserver(token)
            distributedCenter.removeObserver(token)
        }
        tokens.removeAll()
    }

    private func addWorkspace(_ name: Notification.Name, fire: @escaping () -> Void) {
        tokens.append(
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in fire() }
        )
    }

    private func addDistributed(_ rawName: String, fire: @escaping () -> Void) {
        tokens.append(
            distributedCenter.addObserver(
                forName: Notification.Name(rawName),
                object: nil,
                queue: .main
            ) { _ in fire() }
        )
    }

    deinit {
        stop()
    }
}
