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

    /// The failure category raw value (transient, permanent, partial).
    var failureCategoryRaw: String?

    /// The recovery action stored as JSON for permanent failures.
    var recoveryActionData: Data?

    /// Number of destinations that succeeded (for partial failures).
    var partialSuccessCount: Int?

    /// Number of destinations that failed (for partial failures).
    var partialFailureCount: Int?

    /// Whether this was a background sync or a manual foreground sync.
    var isBackgroundSync: Bool

    var status: SyncStatus {
        get { SyncStatus(rawValue: statusRaw) ?? .failure }
        set { statusRaw = newValue.rawValue }
    }

    /// The structured failure category, reconstructed from stored raw values.
    var failureCategory: SyncFailure? {
        guard let raw = failureCategoryRaw else { return nil }
        let message = errorMessage ?? "Unknown error"
        switch raw {
        case "transient":
            return .transient(message: message)
        case "permanent":
            let recovery = recoveryActionData.flatMap { try? JSONDecoder().decode(SyncFailure.RecoveryAction.self, from: $0) }
            return .permanent(message: message, recovery: recovery)
        case "partial":
            return .partial(
                successes: partialSuccessCount ?? 0,
                failures: partialFailureCount ?? 0,
                message: message
            )
        default:
            return nil
        }
    }

    /// The maximum number of characters stored in ``errorMessage``.
    static let maxErrorMessageLength = 200

    /// Applies a ``SyncFailure`` to this record, storing its category, recovery action,
    /// and display message. The error message is truncated to ``maxErrorMessageLength``
    /// characters to prevent SwiftData store bloat.
    func applyFailure(_ failure: SyncFailure) {
        failureCategoryRaw = failure.categoryRaw
        errorMessage = Self.truncateErrorMessage(failure.displayMessage)
        if case let .permanent(_, recovery) = failure {
            recoveryActionData = recovery.flatMap { try? JSONEncoder().encode($0) }
        }
        if case let .partial(successes, failures, _) = failure {
            partialSuccessCount = successes
            partialFailureCount = failures
        }
    }

    /// Truncates a message to ``maxErrorMessageLength`` characters, appending an
    /// ellipsis when truncation occurs.
    private static func truncateErrorMessage(_ message: String?) -> String? {
        guard let message, message.count > maxErrorMessageLength else { return message }
        return String(message.prefix(maxErrorMessageLength - 1)) + "\u{2026}"
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
        self.errorMessage = Self.truncateErrorMessage(errorMessage)
        self.isBackgroundSync = isBackgroundSync
    }
}
