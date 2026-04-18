import Foundation
import Network

// MARK: - NetworkPathMonitoring

/// Reports whether a network path is currently usable for outbound requests.
///
/// Used by the sync engine to defer (rather than fail) when the device is
/// offline. A deferred run is recorded with `.deferred(.offline, ...)` so the
/// user sees an informational entry instead of a red error.
protocol NetworkPathMonitoring: Sendable {
    /// `true` when at least one network interface reports a satisfied path.
    /// Reads the latest snapshot from a long-running `NWPathMonitor`.
    var isReachable: Bool { get }
}

// MARK: - NetworkPathMonitor

/// Production implementation backed by `NWPathMonitor`.
///
/// A single shared monitor runs for the app lifetime — `NWPathMonitor` updates
/// asynchronously, so we need to keep an instance alive to receive callbacks.
final class NetworkPathMonitor: NetworkPathMonitoring, @unchecked Sendable {
    static let shared = NetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.healthpush.NetworkPathMonitor")
    private let lock = NSLock()
    private var cachedStatus: NWPath.Status = .satisfied

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock()
            cachedStatus = path.status
            lock.unlock()
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var isReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedStatus == .satisfied
    }
}
