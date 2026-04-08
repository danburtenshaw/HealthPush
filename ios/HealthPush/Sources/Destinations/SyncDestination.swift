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
/// 3. Implement `sync(data:)` and `testConnection()`.
/// 4. Add a new case to `DestinationType`.
/// 5. Add configuration UI in `Views/Screens/`.
protocol SyncDestination: Identifiable, Sendable {
    /// Unique identifier for this destination instance.
    var id: UUID { get }

    /// Human-readable name for display.
    var name: String { get }

    /// Whether this destination is currently enabled.
    var isEnabled: Bool { get }

    /// Syncs the given health data points to the destination.
    /// - Parameter data: The health data points to sync.
    /// - Returns: Statistics about what was actually written.
    /// - Throws: An error if the sync fails.
    func sync(data: [HealthDataPoint]) async throws -> SyncStats

    /// Tests whether the destination is reachable and properly configured.
    /// - Returns: `true` if the connection test succeeds.
    /// - Throws: An error if the connection test fails.
    func testConnection() async throws -> Bool
}
