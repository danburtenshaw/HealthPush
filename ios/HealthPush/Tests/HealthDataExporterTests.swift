import Foundation
import Testing
@testable import HealthPush

// MARK: - HealthDataExporterTests

struct HealthDataExporterTests {
    private let exporter = HealthDataExporter()

    // MARK: Helpers

    private func makePoint(
        id: UUID = UUID(),
        metricType: HealthMetricType = .heartRate,
        value: Double = 72.0,
        startDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        sourceName: String = "Apple Watch",
        sourceBundleIdentifier: String? = "com.apple.health",
        categoryValue: Int? = nil,
        aggregation: String = "raw"
    ) -> HealthDataPoint {
        HealthDataPoint(
            id: id,
            metricType: metricType,
            value: value,
            unit: metricType.canonicalUnit,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60),
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            categoryValue: categoryValue,
            aggregation: aggregation,
            tzOffset: "+00:00"
        )
    }

    // MARK: CSV Round-Trip

    @Test("CSV round-trip preserves source name with quotes")
    func csvRoundTripWithQuotes() {
        let point = makePoint(sourceName: "Jane's \"Fitbit\"")
        let csv = exporter.encodeCSV([point])
        let decoded = exporter.decodeCSV(csv)

        #expect(decoded.count == 1)
        #expect(decoded[0].sourceName == "Jane's \"Fitbit\"")
        #expect(decoded[0].id == point.id)
        #expect(decoded[0].value == point.value)
    }

    @Test("CSV round-trip preserves source name with commas")
    func csvRoundTripWithCommas() {
        let point = makePoint(sourceName: "GymKit, Treadmill")
        let csv = exporter.encodeCSV([point])
        let decoded = exporter.decodeCSV(csv)

        #expect(decoded.count == 1)
        #expect(decoded[0].sourceName == "GymKit, Treadmill")
    }

    @Test("CSV handles multiple data points")
    func csvRoundTripMultiplePoints() {
        let points = [
            makePoint(value: 72.0, sourceName: "Apple Watch"),
            makePoint(value: 80.0, sourceName: "iPhone")
        ]
        let csv = exporter.encodeCSV(points)
        let decoded = exporter.decodeCSV(csv)

        #expect(decoded.count == 2)
        #expect(decoded[0].sourceName == "Apple Watch")
        #expect(decoded[1].sourceName == "iPhone")
    }

    @Test("CSV header matches v1 schema column order")
    func csvHeaderMatchesV1() {
        #expect(HealthDataExporter.csvHeader == "uuid,startDate,endDate,tzOffset,value,unit,aggregation,sourceName,sourceBundleId,schemaVersion")
    }

    // MARK: JSON Round-Trip

    @Test("JSON round-trip preserves all fields")
    func jsonRoundTrip() throws {
        let original = makePoint(
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            categoryValue: 4
        )
        let json = try exporter.encodeJSON([original])
        let decoded = try exporter.decodeJSON(json)

        #expect(decoded.count == 1)
        #expect(decoded[0].id == original.id)
        #expect(decoded[0].metricType == original.metricType)
        #expect(decoded[0].value == original.value)
        #expect(decoded[0].unit == original.unit)
        #expect(decoded[0].sourceName == original.sourceName)
        #expect(decoded[0].sourceBundleIdentifier == original.sourceBundleIdentifier)
        #expect(decoded[0].categoryValue == 4)
        #expect(decoded[0].schemaVersion == "1.0")
        #expect(decoded[0].aggregation == "raw")
    }

    // MARK: NDJSON Round-Trip

    @Test("NDJSON round-trip preserves all fields")
    func ndjsonRoundTrip() throws {
        let original = makePoint(
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health"
        )
        let ndjson = try exporter.encodeNDJSON([original])
        let decoded = exporter.decodeNDJSON(ndjson)

        #expect(decoded.count == 1)
        #expect(decoded[0].id == original.id)
        #expect(decoded[0].metricType == original.metricType)
        #expect(decoded[0].value == original.value)
    }

    @Test("NDJSON produces one line per point")
    func ndjsonLineCount() throws {
        let points = [
            makePoint(value: 72.0),
            makePoint(value: 80.0)
        ]
        let ndjson = try exporter.encodeNDJSON(points)
        let string = String(data: ndjson, encoding: .utf8) ?? ""
        let lines = string.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 2)
    }

    // MARK: Merge

    @Test("Merge deduplicates by UUID -- same UUID not counted as new")
    func mergeDeduplicatesByUUID() {
        let id = UUID()
        let existing = [makePoint(id: id, value: 72.0)]
        let incoming = [makePoint(id: id, value: 72.0)]

        let result = exporter.merge(existing: existing, incoming: incoming)

        #expect(result.points.count == 1)
        #expect(result.newCount == 0)
    }

    @Test("Merge counts genuinely new points")
    func mergeCountsNewPoints() {
        let existing = [makePoint(id: UUID(), value: 72.0)]
        let incoming = [makePoint(id: UUID(), value: 80.0)]

        let result = exporter.merge(existing: existing, incoming: incoming)

        #expect(result.points.count == 2)
        #expect(result.newCount == 1)
    }

    @Test("Merge counts updated values as changes")
    func mergeCountsUpdatedValues() {
        let id = UUID()
        let existing = [makePoint(id: id, value: 72.0)]
        let incoming = [makePoint(id: id, value: 75.0)]

        let result = exporter.merge(existing: existing, incoming: incoming)

        #expect(result.points.count == 1)
        #expect(result.newCount == 1)
        #expect(result.points[0].value == 75.0)
    }

    @Test("Merge preserves tombstones from incoming data")
    func mergePreservesTombstones() {
        let id = UUID()
        let now = Date()
        let existing = [makePoint(id: id, value: 72.0)]
        let tombstone = HealthDataPoint(
            id: id,
            metricType: .heartRate,
            value: 72.0,
            unit: "count/min",
            startDate: now,
            endDate: now.addingTimeInterval(60),
            sourceName: "Apple Watch",
            deleted: true,
            deletedAt: now
        )

        let result = exporter.merge(existing: existing, incoming: [tombstone])

        #expect(result.points.count == 1)
        #expect(result.newCount == 1)
        #expect(result.points[0].deleted)
    }

    // MARK: Grouping

    @Test("Groups data points by date and metric type")
    func groupByDateAndMetric() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        let day2 = day1.addingTimeInterval(86400) // 2023-11-15

        let points = [
            makePoint(metricType: .steps, startDate: day1),
            makePoint(metricType: .heartRate, startDate: day1),
            makePoint(metricType: .steps, startDate: day2)
        ]

        let grouped = exporter.groupByDateAndMetric(points)

        #expect(grouped.count == 3)
    }

    // MARK: Full Pipeline

    @Test("mergeAndEncode with JSON format produces a valid JSON array")
    func mergeAndEncodeJSON() throws {
        let point = makePoint()
        let result = try exporter.mergeAndEncode(
            existingData: nil,
            incoming: [point],
            format: .json
        )

        #expect(result.newCount == 1)
        let decoded = try exporter.decodeJSON(result.data)
        #expect(decoded.count == 1)
        #expect(decoded[0].id == point.id)
    }

    @Test("mergeAndEncode with NDJSON format produces valid newline-delimited output")
    func mergeAndEncodeNDJSON() throws {
        let point = makePoint()
        let result = try exporter.mergeAndEncode(
            existingData: nil,
            incoming: [point],
            format: .ndjson
        )

        #expect(result.newCount == 1)
        let decoded = exporter.decodeNDJSON(result.data)
        #expect(decoded.count == 1)
        #expect(decoded[0].id == point.id)
    }

    @Test("mergeAndEncode with CSV format produces valid output")
    func mergeAndEncodeCSV() throws {
        let point = makePoint()
        let result = try exporter.mergeAndEncode(
            existingData: nil,
            incoming: [point],
            format: .csv
        )

        #expect(result.newCount == 1)
        let decoded = exporter.decodeCSV(result.data)
        #expect(decoded.count == 1)
        #expect(decoded[0].id == point.id)
    }

    // MARK: Path Building

    @Test("buildKey produces v1 layout path")
    func buildKeyV1Layout() {
        let key = HealthDataExporter.buildKey(
            prefix: "my-data",
            dateString: "2026-04-09",
            metricType: .heartRate,
            ext: "jsonl"
        )
        #expect(key == "my-data/v1/heart_rate/2026/04/09/data.jsonl")
    }

    @Test("buildKey with empty prefix omits leading component")
    func buildKeyEmptyPrefix() {
        let key = HealthDataExporter.buildKey(
            prefix: "",
            dateString: "2026-04-09",
            metricType: .steps,
            ext: "jsonl"
        )
        #expect(key == "v1/steps/2026/04/09/data.jsonl")
    }

    @Test("buildManifestKey produces correct sidecar path")
    func buildManifestKey() {
        let key = HealthDataExporter.buildManifestKey(
            prefix: "my-data",
            dateString: "2026-04-09",
            metricType: .heartRate
        )
        #expect(key == "my-data/v1/heart_rate/2026/04/09/_manifest.json")
    }

    // MARK: Manifest

    @Test("buildManifest produces valid JSON")
    func buildManifest() throws {
        let data = HealthDataExporter.buildManifest(
            metric: "heart_rate",
            dateString: "2026-04-09",
            recordCount: 42,
            lastModified: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["schemaVersion"] as? String == "1.0")
        #expect(json?["metric"] as? String == "heart_rate")
        #expect(json?["date"] as? String == "2026-04-09")
        #expect(json?["recordCount"] as? Int == 42)
        #expect(json?["lastModified"] as? String != nil)
    }
}
