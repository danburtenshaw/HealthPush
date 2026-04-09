import Foundation

#if canImport(os)
import os
#endif

// MARK: - S3SyncStats

/// Statistics returned by the shared S3 sync service.
struct S3SyncStats {
    let processedCount: Int
    let newCount: Int
}

// MARK: - S3SyncService

/// Shared S3 sync logic used by the app and Linux package tests.
struct S3SyncService {
    typealias ProgressHandler = @Sendable (Int, Int) -> Void

    private let s3Client: S3Client
    private let exporter: HealthDataExporter
    private let pathPrefix: String
    private let exportFormat: ExportFormat

    #if canImport(os)
    private let logger = Logger(subsystem: "app.healthpush", category: "S3SyncService")
    #endif

    init(
        s3Client: S3Client,
        pathPrefix: String,
        exportFormat: ExportFormat,
        exporter: HealthDataExporter = HealthDataExporter()
    ) {
        self.s3Client = s3Client
        self.pathPrefix = pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        self.exportFormat = exportFormat
        self.exporter = exporter
    }

    func sync(data: [HealthDataPoint], onProgress: ProgressHandler? = nil) async throws -> S3SyncStats {
        guard !data.isEmpty else {
            #if canImport(os)
            logger.info("No data points to sync to S3")
            #endif
            return S3SyncStats(processedCount: 0, newCount: 0)
        }

        let grouped = exporter.groupByDateAndMetric(data)
        let totalFiles = grouped.count
        let ext = exportFormat == .csv ? "csv" : "jsonl"

        var completed = 0
        var totalNewOrUpdated = 0
        onProgress?(0, totalFiles)

        for (key, points) in grouped {
            let objectKey = HealthDataExporter.buildKey(
                prefix: pathPrefix,
                dateString: key.dateString,
                metricType: key.metricType,
                ext: ext
            )

            let newCount = try await syncFile(key: objectKey, newPoints: points)
            totalNewOrUpdated += newCount

            // Upload _manifest.json sidecar
            let manifestKey = HealthDataExporter.buildManifestKey(
                prefix: pathPrefix,
                dateString: key.dateString,
                metricType: key.metricType
            )
            let mergedCount = try await countMergedRecords(key: objectKey, newPoints: points)
            let manifestData = HealthDataExporter.buildManifest(
                metric: key.metricType.fileStem,
                dateString: key.dateString,
                recordCount: mergedCount,
                lastModified: Date()
            )
            try await s3Client.putObject(
                key: manifestKey,
                data: manifestData,
                contentType: "application/json"
            )

            completed += 1
            onProgress?(completed, totalFiles)
        }

        #if canImport(os)
        logger.info("S3 sync complete: \(totalNewOrUpdated) new/updated across \(grouped.count) files")
        #endif

        return S3SyncStats(processedCount: data.count, newCount: totalNewOrUpdated)
    }

    func testConnection() async throws -> Bool {
        try await s3Client.testConnection()
    }

    @discardableResult
    private func syncFile(key: String, newPoints: [HealthDataPoint]) async throws -> Int {
        let existingData = try await s3Client.getObject(key: key)
        let result = try exporter.mergeAndEncode(
            existingData: existingData,
            incoming: newPoints,
            format: exportFormat
        )

        let contentType = exportFormat == .csv ? "text/csv" : "application/x-ndjson"
        try await s3Client.putObject(
            key: key,
            data: result.data,
            contentType: contentType
        )

        return result.newCount
    }

    private func countMergedRecords(key: String, newPoints: [HealthDataPoint]) async throws -> Int {
        let existingData = try await s3Client.getObject(key: key)
        let existing: [HealthDataPoint] = if let data = existingData {
            switch exportFormat {
            case .json:
                exporter.decodeNDJSON(data)
            case .csv:
                exporter.decodeCSV(data)
            }
        } else {
            []
        }
        let merged = exporter.merge(existing: existing, incoming: newPoints)
        return merged.points.count
    }
}
