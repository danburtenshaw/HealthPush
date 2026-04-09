import Foundation

/// Describes the sync behavior and capabilities of a destination.
///
/// Each ``SyncDestination`` exposes a ``SyncCapabilities`` value so the
/// ``SyncEngine`` can adapt its query and delivery strategy without
/// switching on destination type.
struct SyncCapabilities: Sendable, Equatable {
    /// Whether the destination supports incremental sync (only new data since last sync).
    let supportsIncremental: Bool

    /// Whether each sync overwrites the full file (like S3's read-merge-write).
    let isIdempotent: Bool

    /// Whether the destination is fire-and-forget (like HA webhook -- sends latest value, no merge).
    let isFireAndForget: Bool

    /// Maximum batch size, or nil for unlimited.
    let maxBatchSize: Int?
}
