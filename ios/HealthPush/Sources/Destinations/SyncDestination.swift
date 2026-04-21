import Foundation

// MARK: - SyncStats

/// Statistics returned by a destination after syncing.
///
/// Destinations report how many data points were processed vs. how many
/// were actually new or updated. This lets the UI show meaningful counts
/// rather than the total HealthKit query size.
struct SyncStats {
    /// Total data points the destination received.
    let processedCount: Int

    /// Data points that were actually new or changed (not duplicates).
    let newCount: Int
}

// MARK: - SyncDestination

/// Protocol that all sync destinations must conform to.
///
/// Each destination (Home Assistant, CSV, Google Sheets, etc.) implements this protocol
/// to define how health data is transmitted. Destinations must be `Sendable` for
/// safe use across concurrency domains.
///
/// ## Adding a New Destination
///
/// 1. Create a new file in `Sources/Destinations/`.
/// 2. Create a struct conforming to `SyncDestination`.
/// 3. Implement all required methods including `sync(data:onProgress:)`.
/// 4. Add a new case to `DestinationType`.
/// 5. Add configuration UI in `Views/Screens/`.
protocol SyncDestination: Identifiable, Sendable {
    /// Unique identifier for this destination instance.
    var id: UUID { get }

    /// Human-readable name for display.
    var name: String { get }

    /// Whether this destination is currently enabled.
    var isEnabled: Bool { get }

    /// The destination's sync capabilities.
    var capabilities: SyncCapabilities { get }

    /// Returns the query window for discrete metrics based on sync state.
    ///
    /// - Parameters:
    ///   - lastSyncedAt: When this destination was last successfully synced, or nil if never.
    ///   - needsFullSync: Whether a full (non-incremental) sync has been requested.
    ///   - now: The current time (injectable for testing).
    /// - Returns: The date range to query HealthKit for discrete metrics.
    func queryWindow(lastSyncedAt: Date?, needsFullSync: Bool, now: Date) -> QueryWindow

    /// Returns the query window for cumulative metrics, or nil to reuse the discrete window.
    ///
    /// Some destinations need a different window for cumulative metrics. For example,
    /// Home Assistant always queries from start-of-day to report full daily totals.
    ///
    /// - Parameters:
    ///   - lastSyncedAt: When this destination was last successfully synced, or nil if never.
    ///   - needsFullSync: Whether a full (non-incremental) sync has been requested —
    ///     e.g. the user changed the "Sync From" date. Destinations that back up
    ///     historical daily totals (like S3) should widen the window accordingly.
    ///   - now: The current time (injectable for testing).
    /// - Returns: A query window for cumulative metrics, or nil to use the discrete window.
    func cumulativeQueryWindow(lastSyncedAt: Date?, needsFullSync: Bool, now: Date) -> QueryWindow?

    /// Syncs health data with progress reporting.
    ///
    /// - Parameters:
    ///   - data: The health data points to sync.
    ///   - onProgress: Optional callback reporting (completedItems, totalItems).
    /// - Returns: Statistics about what was actually written.
    /// - Throws: An error if the sync fails.
    func sync(data: [HealthDataPoint], onProgress: (@Sendable (Int, Int) -> Void)?) async throws -> SyncStats

    /// Tests whether the destination is reachable and properly configured.
    /// - Returns: `true` if the connection test succeeds.
    /// - Throws: An error if the connection test fails.
    func testConnection() async throws -> Bool

    /// Classifies a sync error into a ``SyncFailure`` for retry decisions and UI recovery.
    ///
    /// Each destination maps its own error types to the generic failure taxonomy.
    /// The default implementation returns `.transient` for all errors.
    func classifyError(_ error: Error) -> SyncFailure
}

// MARK: - SyncDestination Defaults

extension SyncDestination {
    /// Convenience overload that syncs without progress reporting.
    func sync(data: [HealthDataPoint]) async throws -> SyncStats {
        try await sync(data: data, onProgress: nil)
    }

    /// Default error classification using common network error patterns.
    func classifyError(_ error: Error) -> SyncFailure {
        SyncFailure.classifyNetworkError(error)
    }
}
