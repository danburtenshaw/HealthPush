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

/// Syncs health data to Amazon S3, storing one file per date/metric combination.
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

    private let s3Client: S3Client
    private let exporter: HealthDataExporter
    private let pathPrefix: String
    private let exportFormat: ExportFormat
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
    /// - `s3Region` → AWS region
    /// - `s3PathPrefix` → Object key prefix
    /// - `s3ExportFormatRaw` → Export format
    init(config: DestinationConfig, migrateSecretsIfNeeded: Bool = true) throws {
        self.id = config.id
        self.name = config.name
        self.isEnabled = config.isEnabled
        self.pathPrefix = config.s3PathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        self.exportFormat = config.exportFormat
        self.exporter = HealthDataExporter()
        self.s3Client = S3Client(
            bucket: config.baseURL,
            region: config.s3Region.isEmpty ? "us-east-1" : config.s3Region,
            accessKeyID: try config.apiTokenValue(migratingIfNeeded: migrateSecretsIfNeeded),
            secretAccessKey: try config.s3SecretAccessKeyValue(migratingIfNeeded: migrateSecretsIfNeeded)
        )
    }

    // MARK: SyncDestination

    func sync(data: [HealthDataPoint]) async throws -> SyncStats {
        try await sync(data: data, onProgress: nil)
    }

    /// Syncs health data to S3 with progress reporting.
    func sync(data: [HealthDataPoint], onProgress: ProgressHandler?) async throws -> SyncStats {
        guard !data.isEmpty else {
            logger.info("No data points to sync to S3")
            return SyncStats(processedCount: 0, newCount: 0)
        }

        // Use the shared exporter to group by date and metric
        let grouped = exporter.groupByDateAndMetric(data)

        let totalFiles = grouped.count
        var completed = 0
        var totalNewOrUpdated = 0
        onProgress?(0, totalFiles)

        // Process each date/metric combination
        let ext = exportFormat == .csv ? "csv" : "json"

        for (key, points) in grouped {
            let s3Key = HealthDataExporter.buildKey(
                prefix: pathPrefix,
                dateString: key.dateString,
                metricType: key.metricType,
                ext: ext
            )

            let newCount = try await syncFile(key: s3Key, newPoints: points, format: exportFormat)
            totalNewOrUpdated += newCount

            completed += 1
            onProgress?(completed, totalFiles)
        }

        logger.info("S3 sync complete: \(totalNewOrUpdated) new/updated across \(grouped.count) files")
        return SyncStats(processedCount: data.count, newCount: totalNewOrUpdated)
    }

    func testConnection() async throws -> Bool {
        try await s3Client.testConnection()
    }

    // MARK: Private

    /// Downloads an existing file, merges new data, and uploads the result.
    /// - Returns: The number of genuinely new or updated data points in this file.
    @discardableResult
    private func syncFile(key: String, newPoints: [HealthDataPoint], format: ExportFormat) async throws -> Int {
        // Fetch existing data (nil if file doesn't exist yet)
        let existingData = try await s3Client.getObject(key: key)

        // Merge and encode using the shared exporter
        let result = try exporter.mergeAndEncode(
            existingData: existingData,
            incoming: newPoints,
            format: format
        )

        // Upload
        let contentType = format == .csv ? "text/csv" : "application/json"
        try await s3Client.putObject(key: key, data: result.data, contentType: contentType)

        return result.newCount
    }
}
