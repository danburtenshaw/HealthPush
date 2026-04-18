import BackgroundTasks
import Foundation

// MARK: - BGTaskScheduling

/// Abstracts `BGTaskScheduler` so the sync scheduler can be tested without
/// the real system service.
///
/// In production this is satisfied by `BGTaskScheduler.shared`. In tests we
/// inject a fake that records `submit` calls and lets us drive task handlers
/// synchronously.
@MainActor
protocol BGTaskScheduling: AnyObject {
    /// Submits a `BGTaskRequest` to the scheduler. Throws on invalid identifier
    /// or unmet preconditions.
    func submit(_ request: BGTaskRequest) throws

    /// Cancels all pending requests for the given identifier.
    func cancel(taskRequestWithIdentifier identifier: String)

    /// Cancels every pending task request known to the app.
    func cancelAllTaskRequests()

    /// Returns the identifiers of every pending request. Used to avoid
    /// re-submitting a request that's already scheduled.
    func pendingTaskIdentifiers() async -> [String]
}

// MARK: - BGTaskScheduler conformance

extension BGTaskScheduler: BGTaskScheduling {
    /// Bridges `getPendingTaskRequests` (callback-based) to async/await.
    func pendingTaskIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            getPendingTaskRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }
}
