import Foundation

// MARK: - SyncFailure

/// Categorizes sync failures to drive retry behavior and UI recovery.
///
/// Each failed or partially failed sync records a `SyncFailure` category on its
/// ``SyncRecord``. The background scheduler uses ``isRetryable`` to decide whether
/// to schedule another attempt, and the dashboard uses ``recoveryAction`` to show
/// user-actionable guidance.
enum SyncFailure: Sendable, Equatable {
    /// A temporary error that may resolve on its own (network timeout, server 5xx, etc.).
    case transient(message: String)

    /// A permanent error requiring user intervention (invalid credentials, wrong URL, etc.).
    case permanent(message: String, recovery: RecoveryAction?)

    /// Some destinations succeeded while others failed.
    case partial(successes: Int, failures: Int, message: String)

    /// Whether this failure should be retried automatically.
    var isRetryable: Bool {
        switch self {
        case .transient: true
        case .permanent: false
        case .partial: true
        }
    }

    /// A human-readable summary for the UI.
    var displayMessage: String {
        switch self {
        case let .transient(message): message
        case let .permanent(message, _): message
        case let .partial(successes, failures, message):
            "\(successes) succeeded, \(failures) failed: \(message)"
        }
    }

    /// Raw string for storage in ``SyncRecord/failureCategoryRaw``.
    var categoryRaw: String {
        switch self {
        case .transient: "transient"
        case .permanent: "permanent"
        case .partial: "partial"
        }
    }

    /// The recovery action, if any. Only meaningful for ``permanent`` failures.
    var recoveryAction: RecoveryAction? {
        switch self {
        case let .permanent(_, recovery): recovery
        default: nil
        }
    }
}

// MARK: - SyncFailure.RecoveryAction

extension SyncFailure {
    /// User-actionable recovery suggestion for permanent failures.
    ///
    /// Destinations provide fully formed recovery actions so the UI
    /// never needs destination-specific switch statements.
    struct RecoveryAction: Codable, Sendable, Equatable {
        /// Stable identifier for persistence (e.g. "reauthenticate").
        let id: String
        /// Button title shown in the UI (e.g. "Check Credentials").
        let buttonTitle: String
        /// Guidance text shown in the UI (e.g. "Check your credentials in the destination settings.").
        let guidance: String
    }
}

// MARK: - Network Error Classification

extension SyncFailure {
    /// Classifies common network errors. Destinations call this from their `classifyError`
    /// for errors they don't handle specifically.
    static func classifyNetworkError(_ error: Error) -> SyncFailure {
        if let networkError = error as? NetworkError {
            switch networkError {
            case let .httpError(statusCode, _) where statusCode == 401 || statusCode == 403:
                return .permanent(message: error.localizedDescription, recovery: .reauthenticate)
            case .timeout, .connectionFailed:
                return .transient(message: error.localizedDescription)
            default:
                break
            }
        }
        return .transient(message: error.localizedDescription)
    }
}

// MARK: - Common Recovery Actions

extension SyncFailure.RecoveryAction {
    static let reauthenticate = SyncFailure.RecoveryAction(
        id: "reauthenticate",
        buttonTitle: "Check Credentials",
        guidance: "Check your credentials in the destination settings."
    )
    static let fixURL = SyncFailure.RecoveryAction(
        id: "fixURL",
        buttonTitle: "Fix URL",
        guidance: "The destination URL appears to be incorrect."
    )
    static let fixBucketConfig = SyncFailure.RecoveryAction(
        id: "fixBucketConfig",
        buttonTitle: "Fix Bucket Config",
        guidance: "Review the S3 bucket and region settings."
    )
    static let enableMetrics = SyncFailure.RecoveryAction(
        id: "enableMetrics",
        buttonTitle: "Enable Metrics",
        guidance: "No health metrics are enabled for this destination."
    )
}
