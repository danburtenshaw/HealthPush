import Foundation
import os

// MARK: - S3DestinationError

/// Errors specific to S3 destination operations.
enum S3DestinationError: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg):
            return "Invalid S3 configuration: \(msg)"
        case .syncFailed(let msg):
            return "S3 sync failed: \(msg)"
        }
    }
}

// MARK: - S3Destination

/// Syncs health data to S3-compatible storage, storing one file per date/metric combination.
///
/// Uses the shared ``HealthDataExporter`` for data grouping, UUID-based deduplication,
/// and format serialization. The S3-specific logic is limited to file retrieval and upload.
///
/// ## File Structure
///
/// Files are organised as:
/// ```
/// <path-prefix>/<YYYY-MM-DD>/<metric_name>.json
/// <path-prefix>/<YYYY-MM-DD>/<metric_name>.csv
/// ```
///
/// ## Merge Strategy
///
/// On each sync the destination:
/// 1. Groups incoming data by date and metric type
/// 2. For each group, downloads the existing S3 object (if any)
/// 3. Merges new data with existing data, deduplicating by HealthKit UUID
/// 4. Uploads the merged result, overwriting the previous file
///
/// This means frequent syncs (minutely, hourly) are safe — they produce
/// the same result as a single sync covering the full window.
struct S3Destination: SyncDestination {

    // MARK: Properties

    let id: UUID
    let name: String
    let isEnabled: Bool

    private let syncService: S3SyncService
    private let logger = Logger(subsystem: "com.healthpush.app", category: "S3Destination")

    /// Progress callback: (filesCompleted, totalFiles).
    typealias ProgressHandler = @Sendable (Int, Int) -> Void

    // MARK: Initialization

    /// Creates an S3 destination from a persisted configuration.
    ///
    /// Field mapping from ``DestinationConfig``:
    /// - `baseURL` → S3 bucket name
    /// - `apiToken` → AWS access key ID
    /// - `s3SecretAccessKey` → AWS secret access key
    /// - `s3Region` → S3 signing region
    /// - `s3PathPrefix` → Object key prefix
    /// - `s3Endpoint` → Optional custom S3-compatible endpoint
    /// - `s3ExportFormatRaw` → Export format
    init(config: DestinationConfig, migrateSecretsIfNeeded: Bool = true) throws {
        self.id = config.id
        self.name = config.name
        self.isEnabled = config.isEnabled
        let s3Client = S3Client(
            bucket: config.baseURL,
            region: config.s3Region.isEmpty ? "us-east-1" : config.s3Region,
            accessKeyID: try config.apiTokenValue(migratingIfNeeded: migrateSecretsIfNeeded),
            secretAccessKey: try config.s3SecretAccessKeyValue(migratingIfNeeded: migrateSecretsIfNeeded),
            endpointOverride: config.s3Endpoint
        )
        self.syncService = S3SyncService(
            s3Client: s3Client,
            pathPrefix: config.s3PathPrefix,
            exportFormat: config.exportFormat
        )
    }

    // MARK: SyncDestination

    func sync(data: [HealthDataPoint]) async throws -> SyncStats {
        try await sync(data: data, onProgress: nil)
    }

    /// Syncs health data to S3 with progress reporting.
    func sync(data: [HealthDataPoint], onProgress: ProgressHandler?) async throws -> SyncStats {
        let stats = try await syncService.sync(data: data, onProgress: onProgress)
        logger.info("S3 destination sync complete: \(stats.newCount) new/updated")
        return SyncStats(processedCount: stats.processedCount, newCount: stats.newCount)
    }

    func testConnection() async throws -> Bool {
        try await syncService.testConnection()
    }
}
