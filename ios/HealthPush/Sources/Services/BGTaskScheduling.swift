import BackgroundTasks
import Foundation

// MARK: - BGTaskScheduling

/// Abstracts `BGTaskScheduler` so the sync scheduler can be tested without
/// the real system service.
///
/// In production this is satisfied by `BGTaskScheduler.shared`. In tests we
/// inject a fake that records `submit` calls and lets us drive task handlers
/// synchronously.
///
/// The protocol is `Sendable` (not `@MainActor`-isolated) so the existential
/// `any BGTaskScheduling` can cross actor boundaries — `BackgroundSyncScheduler`
/// is `@MainActor` and awaits `pendingTaskIdentifiers()` from there. We can't
/// make the protocol `@MainActor`-isolated because that would force a
/// retroactive `Sendable` conformance on `BGTaskScheduler` (a class we don't
/// own), which Swift 6 strict concurrency rejects without an explicit
/// `@unchecked @retroactive Sendable` extension. The latter is below.
protocol BGTaskScheduling: AnyObject, Sendable {
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

/// `BGTaskScheduler` isn't annotated `Sendable` in the BackgroundTasks SDK, but
/// Apple documents its instance methods (`submit`, `cancel*`,
/// `getPendingTaskRequests`) as safe to call from any thread. Declare the
/// retroactive Sendable conformance explicitly so Swift 6 strict concurrency
/// allows the conformance to `BGTaskScheduling` below.
extension BGTaskScheduler: @unchecked @retroactive Sendable { }

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
