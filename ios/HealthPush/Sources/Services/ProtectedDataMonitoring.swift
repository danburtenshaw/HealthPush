import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ProtectedDataMonitoring

/// Reports whether iOS file-protected data (including HealthKit) is currently
/// readable, and notifies when that changes.
///
/// HealthKit's data store is encrypted while the device is locked. Apple's docs
/// state: "The HealthKit datastore is inaccessible when the device is locked.
/// Access to the data is relinquished 10 minutes after the device locks, and
/// data becomes accessible the next time user enters their passcode or uses
/// Face ID or Touch ID to unlock the device."
///
/// Background syncs that fire while protected data is unavailable will get
/// empty reads. This protocol lets the scheduler defer such runs cleanly
/// instead of recording them as failures.
@MainActor
protocol ProtectedDataMonitoring: AnyObject, Sendable {
    /// Whether protected data is currently readable.
    var isProtectedDataAvailable: Bool { get }

    /// Registers a one-shot callback fired the next time protected data becomes
    /// available. The callback runs at most once; the implementation removes
    /// the underlying observer after firing.
    func onNextProtectedDataAvailable(_ handler: @escaping @MainActor () -> Void)
}

// MARK: - ProtectedDataMonitor

/// Production implementation backed by `UIApplication.isProtectedDataAvailable`
/// and `protectedDataDidBecomeAvailableNotification`.
@MainActor
final class ProtectedDataMonitor: ProtectedDataMonitoring {
    static let shared = ProtectedDataMonitor()

    private var pendingHandlers: [@MainActor () -> Void] = []
    private var observerToken: NSObjectProtocol?

    private init() { }

    var isProtectedDataAvailable: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.isProtectedDataAvailable
        #else
        return true
        #endif
    }

    func onNextProtectedDataAvailable(_ handler: @escaping @MainActor () -> Void) {
        #if canImport(UIKit)
        pendingHandlers.append(handler)
        guard observerToken == nil else { return }

        observerToken = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification fires on the main queue per `queue: .main`, but
            // bridge into the MainActor explicitly for Sendable safety.
            Task { @MainActor in
                self?.fireAndClearHandlers()
            }
        }
        #else
        // Non-UIKit platforms (Linux tests) — protected data is always available.
        Task { @MainActor in
            handler()
        }
        #endif
    }

    private func fireAndClearHandlers() {
        let handlers = pendingHandlers
        pendingHandlers.removeAll()
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
        for handler in handlers {
            handler()
        }
    }
}
