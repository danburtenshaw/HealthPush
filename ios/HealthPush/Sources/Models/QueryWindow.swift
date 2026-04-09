import Foundation

/// A date range for querying health data.
///
/// Used by ``SyncDestination`` implementations to communicate the appropriate
/// HealthKit query window back to the ``SyncEngine``, keeping the engine
/// destination-agnostic.
struct QueryWindow: Sendable {
    /// The inclusive start of the query range.
    let start: Date

    /// The exclusive end of the query range.
    let end: Date
}
