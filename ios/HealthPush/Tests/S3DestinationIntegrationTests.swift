import Foundation
import Testing
@testable import HealthPush

// MARK: - S3DestinationIntegrationTests

@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["MINIO_ENDPOINT"] != nil
            && ProcessInfo.processInfo.environment["MINIO_BUCKET"] != nil
            && ProcessInfo.processInfo.environment["MINIO_REGION"] != nil
            && ProcessInfo.processInfo.environment["MINIO_ACCESS_KEY_ID"] != nil
            && ProcessInfo.processInfo.environment["MINIO_SECRET_ACCESS_KEY"] != nil,
        "MinIO integration environment is not configured"
    )
)
struct S3DestinationIntegrationTests {
    @Test("MinIO connection test succeeds")
    func connectionAgainstMinIO() async throws {
        let integration = minioIntegration()
        let config = makeConfig(integration: integration, pathPrefix: uniquePrefix("connection"))
        defer { try? config.deleteAllCredentials() }
        let destination = try S3Destination(config: config)

        #expect(try await destination.testConnection())
    }

    @Test("JSON sync uploads and merges objects in MinIO")
    func jsonSyncMergesObjects() async throws {
        let integration = minioIntegration()
        let prefix = uniquePrefix("json")
        let config = makeConfig(integration: integration, pathPrefix: prefix, exportFormat: .json)
        defer { try? config.deleteAllCredentials() }
        let destination = try S3Destination(config: config)

        let firstID = UUID()
        let secondID = UUID()

        let firstBatch = [
            makePoint(id: firstID, value: 72),
            makePoint(id: secondID, value: 75, minutesAfterStart: 5)
        ]
        let secondBatch = [
            makePoint(id: secondID, value: 76, minutesAfterStart: 5),
            makePoint(id: UUID(), value: 78, minutesAfterStart: 10)
        ]

        let firstStats = try await destination.sync(data: firstBatch)
        let secondStats = try await destination.sync(data: secondBatch)

        #expect(firstStats.newCount == 2)
        #expect(secondStats.newCount == 2)

        let storedPoints = try await fetchStoredPoints(
            integration: integration,
            prefix: prefix,
            metricType: .heartRate,
            format: .json
        )

        #expect(storedPoints.count == 3)
        #expect(storedPoints.contains { $0.id == firstID && $0.value == 72 })
        #expect(storedPoints.contains { $0.id == secondID && $0.value == 76 })
        #expect(storedPoints.contains { $0.value == 78 })
    }

    @Test("CSV sync writes readable data to MinIO")
    func csvSyncWritesReadableObjects() async throws {
        let integration = minioIntegration()
        let prefix = uniquePrefix("csv")
        let config = makeConfig(integration: integration, pathPrefix: prefix, exportFormat: .csv)
        defer { try? config.deleteAllCredentials() }
        let destination = try S3Destination(config: config)

        let data = [
            makePoint(id: UUID(), metricType: .steps, value: 4321),
            makePoint(id: UUID(), metricType: .steps, value: 5678, minutesAfterStart: 30)
        ]

        let stats = try await destination.sync(data: data)
        #expect(stats.newCount == 2)

        let storedPoints = try await fetchStoredPoints(
            integration: integration,
            prefix: prefix,
            metricType: .steps,
            format: .csv
        )

        #expect(storedPoints.count == 2)
        #expect(storedPoints.map(\.value).sorted() == [4321, 5678])
    }

    private func fetchStoredPoints(
        integration: MinIOIntegration,
        prefix: String,
        metricType: HealthMetricType,
        format: ExportFormat
    ) async throws -> [HealthDataPoint] {
        let client = S3Client(
            bucket: integration.bucket,
            region: integration.region,
            accessKeyID: integration.accessKeyID,
            secretAccessKey: integration.secretAccessKey,
            endpointOverride: integration.endpoint
        )

        let exporter = HealthDataExporter()
        let dateKey = try #require(exporter.groupByDateAndMetric([makePoint(metricType: metricType, value: 1)]).keys.first)
        let ext = format == .csv ? "csv" : "jsonl"
        let key = HealthDataExporter.buildKey(
            prefix: prefix,
            dateString: dateKey.dateString,
            metricType: metricType,
            ext: ext
        )

        let object = try await client.getObject(key: key)
        let storedData = try #require(object)

        switch format {
        case .json:
            return exporter.decodeNDJSON(storedData)
        case .csv:
            return exporter.decodeCSV(storedData)
        }
    }

    private func makeConfig(
        integration: MinIOIntegration,
        pathPrefix: String,
        exportFormat: ExportFormat = .json
    ) -> DestinationConfig {
        let config = DestinationConfig(
            name: "MinIO",
            destinationType: .s3,
            typeConfig: .s3(S3TypeConfig(
                bucket: integration.bucket,
                region: integration.region,
                endpoint: integration.endpoint,
                pathPrefix: pathPrefix,
                exportFormatRaw: exportFormat.rawValue,
                syncStartDateOptionRaw: SyncStartDateOption.last7Days.rawValue,
                syncStartDateCustom: nil
            )),
            enabledMetrics: [.heartRate, .steps]
        )
        try? config.setCredential(integration.accessKeyID, for: CredentialField.accessKeyID)
        try? config.setCredential(integration.secretAccessKey, for: CredentialField.secretAccessKey)
        return config
    }

    private func makePoint(
        id: UUID = UUID(),
        metricType: HealthMetricType = .heartRate,
        value: Double,
        minutesAfterStart: Double = 0
    ) -> HealthDataPoint {
        let start = Date(timeIntervalSince1970: 1_710_000_000 + (minutesAfterStart * 60))
        return HealthDataPoint(
            id: id,
            metricType: metricType,
            value: value,
            unit: metricType.canonicalUnit,
            startDate: start,
            endDate: start.addingTimeInterval(60),
            sourceName: "Integration Test"
        )
    }

    private func uniquePrefix(_ name: String) -> String {
        "integration-tests/\(name)/\(UUID().uuidString.lowercased())"
    }

    private func minioIntegration() -> MinIOIntegration {
        let env = ProcessInfo.processInfo.environment

        let endpoint = env["MINIO_ENDPOINT"]!
        let bucket = env["MINIO_BUCKET"]!
        let region = env["MINIO_REGION"]!
        let accessKeyID = env["MINIO_ACCESS_KEY_ID"]!
        let secretAccessKey = env["MINIO_SECRET_ACCESS_KEY"]!

        return MinIOIntegration(
            endpoint: endpoint,
            bucket: bucket,
            region: region,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey
        )
    }
}

// MARK: - MinIOIntegration

private struct MinIOIntegration {
    let endpoint: String
    let bucket: String
    let region: String
    let accessKeyID: String
    let secretAccessKey: String
}
