import Foundation
import SwiftData

// MARK: - SyncStatus

/// The outcome of a sync operation.
enum SyncStatus: String, Codable {
    case success
    case partialFailure
    case failure
    case inProgress
}

// MARK: - SyncRecord

/// Persistent record of a sync operation stored via SwiftData.
///
/// Each time the sync engine runs, one `SyncRecord` is created per destination
/// to track what happened.
@Model
final class SyncRecord {
    /// Unique identifier.
    var id: UUID

    /// Name of the destination this sync was targeting.
    var destinationName: String

    /// UUID of the destination configuration.
    var destinationID: UUID

    /// When the sync started.
    var timestamp: Date

    /// How long the sync took in seconds.
    var duration: TimeInterval

    /// Number of data points synced.
    var dataPointCount: Int

    /// Outcome of the sync.
    var statusRaw: String

    /// Human-readable error message, if any.
    var errorMessage: String?

    /// Whether this was a background sync or a manual foreground sync.
    var isBackgroundSync: Bool

    var status: SyncStatus {
        get { SyncStatus(rawValue: statusRaw) ?? .failure }
        set { statusRaw = newValue.rawValue }
    }

    /// Creates a new sync record.
    /// - Parameters:
    ///   - destinationName: The display name of the destination.
    ///   - destinationID: The unique ID of the destination configuration.
    ///   - timestamp: When the sync occurred.
    ///   - duration: How long it took.
    ///   - dataPointCount: Number of data points sent.
    ///   - status: Outcome of the sync.
    ///   - errorMessage: Optional error description.
    ///   - isBackgroundSync: Whether this ran in the background.
    init(
        destinationName: String,
        destinationID: UUID,
        timestamp: Date = .now,
        duration: TimeInterval = 0,
        dataPointCount: Int = 0,
        status: SyncStatus = .inProgress,
        errorMessage: String? = nil,
        isBackgroundSync: Bool = false
    ) {
        id = UUID()
        self.destinationName = destinationName
        self.destinationID = destinationID
        self.timestamp = timestamp
        self.duration = duration
        self.dataPointCount = dataPointCount
        statusRaw = status.rawValue
        self.errorMessage = errorMessage
        self.isBackgroundSync = isBackgroundSync
    }
}
