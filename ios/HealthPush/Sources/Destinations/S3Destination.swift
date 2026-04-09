import Foundation
import os

// MARK: - S3DestinationError

/// Errors specific to S3 destination operations.
enum S3DestinationError: LocalizedError {
    case invalidConfiguration(String)
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(msg):
            "Invalid S3 configuration: \(msg)"
        case let .syncFailed(msg):
            "S3 sync failed: \(msg)"
        }
    }
}

// MARK: - S3Destination

/// Syncs health data to S3-compatible storage, storing one file per date/metric combination.
///
/// Uses the shared ``HealthDataExporter`` for data grouping, UUID-based deduplication,
/// and format serialization. The S3-specific logic is limited to file retrieval and upload.
///
/// ## File Structure (v1 Schema)
///
/// Files are organised as:
/// ```
/// <path-prefix>/v1/<metric_key>/<YYYY>/<MM>/<DD>/data.jsonl
/// <path-prefix>/v1/<metric_key>/<YYYY>/<MM>/<DD>/_manifest.json
/// ```
///
/// ## Merge Strategy
///
/// On each sync the destination:
/// 1. Groups incoming data by date and metric type
/// 2. For each group, downloads the existing S3 object (if any)
/// 3. Merges new data with existing data, deduplicating by HealthKit UUID
/// 4. Uploads the merged NDJSON result, overwriting the previous file
/// 5. Uploads a `_manifest.json` sidecar with record count and last-modified time
///
/// This means frequent syncs (minutely, hourly) are safe — they produce
/// the same result as a single sync covering the full window.
struct S3Destination: SyncDestination {
    // MARK: Properties

    let id: UUID
    let name: String
    let isEnabled: Bool

    /// The resolved start date for full syncs, captured at init from the S3 type config.
    private let fullSyncStartDate: Date

    private let syncService: S3SyncService
    private let logger = Logger(subsystem: "app.healthpush", category: "S3Destination")

    // MARK: Initialization

    /// Creates an S3 destination from a persisted configuration.
    init(config: DestinationConfig) throws {
        id = config.id
        name = config.name
        isEnabled = config.isEnabled
        let s3Config = try config.s3Config
        fullSyncStartDate = s3Config.resolvedSyncStartDate
        let s3Client = try S3Client(
            bucket: s3Config.bucket,
            region: s3Config.region.isEmpty ? "us-east-1" : s3Config.region,
            accessKeyID: config.credential(for: CredentialField.accessKeyID),
            secretAccessKey: config.credential(for: CredentialField.secretAccessKey),
            endpointOverride: s3Config.endpoint
        )
        syncService = S3SyncService(
            s3Client: s3Client,
            pathPrefix: s3Config.pathPrefix,
            exportFormat: s3Config.exportFormat
        )
    }

    // MARK: SyncDestination

    var capabilities: SyncCapabilities {
        SyncCapabilities(supportsIncremental: false, isIdempotent: true, isFireAndForget: false, maxBatchSize: nil)
    }

    func queryWindow(lastSyncedAt: Date?, needsFullSync: Bool, now: Date) -> QueryWindow {
        if needsFullSync {
            return QueryWindow(start: fullSyncStartDate, end: now)
        }
        // 3-day rolling lookback for delayed Apple Watch data
        let start = Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
        return QueryWindow(start: start, end: now)
    }

    func cumulativeQueryWindow(lastSyncedAt: Date?, now: Date) -> QueryWindow? {
        nil // S3 uses the same window for cumulative and discrete
    }

    /// Syncs health data to S3 with progress reporting.
    func sync(data: [HealthDataPoint], onProgress: (@Sendable (Int, Int) -> Void)?) async throws -> SyncStats {
        let stats = try await syncService.sync(data: data, onProgress: onProgress)
        logger.info("S3 destination sync complete: \(stats.newCount) new/updated")
        return SyncStats(processedCount: stats.processedCount, newCount: stats.newCount)
    }

    func testConnection() async throws -> Bool {
        try await syncService.testConnection()
    }

    func classifyError(_ error: Error) -> SyncFailure {
        if let s3Error = error as? S3DestinationError {
            switch s3Error {
            case .invalidConfiguration:
                return .permanent(message: error.localizedDescription, recovery: Self.fixBucketConfig)
            case .syncFailed:
                return SyncFailure.classifyNetworkError(error)
            }
        }
        return SyncFailure.classifyNetworkError(error)
    }

    /// S3-specific recovery action for bucket/region misconfiguration.
    private static let fixBucketConfig = SyncFailure.RecoveryAction(
        id: "fixBucketConfig",
        buttonTitle: "Fix Bucket Config",
        guidance: "Review the S3 bucket and region settings."
    )
}
