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
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        sourceName: String = "Apple Watch",
        sourceBundleIdentifier: String? = "com.apple.health",
        categoryValue: Int? = nil
    ) -> HealthDataPoint {
        HealthDataPoint(
            id: id,
            metricType: metricType,
            value: value,
            unit: metricType.unitString,
            timestamp: timestamp,
            endTimestamp: timestamp.addingTimeInterval(60),
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            categoryValue: categoryValue
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
        let point = makePoint(sourceName: "GymKit, Treadmill", categoryValue: 3)
        let csv = exporter.encodeCSV([point])
        let decoded = exporter.decodeCSV(csv)

        #expect(decoded.count == 1)
        #expect(decoded[0].sourceName == "GymKit, Treadmill")
        #expect(decoded[0].categoryValue == 3)
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

    // MARK: JSON Round-Trip

    @Test("JSON round-trip preserves all fields")
    func jsonRoundTrip() throws {
        let original = makePoint(
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            categoryValue: 4
        )
        let json = try exporter.encodeJSON([original])
        let decoded = exporter.decodeJSON(json)

        #expect(decoded.count == 1)
        #expect(decoded[0].id == original.id)
        #expect(decoded[0].metricType == original.metricType)
        #expect(decoded[0].value == original.value)
        #expect(decoded[0].unit == original.unit)
        #expect(decoded[0].sourceName == original.sourceName)
        #expect(decoded[0].sourceBundleIdentifier == original.sourceBundleIdentifier)
        #expect(decoded[0].categoryValue == 4)
    }

    // MARK: Merge

    @Test("Merge deduplicates by UUID — same UUID not counted as new")
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

    // MARK: Grouping

    @Test("Groups data points by date and metric type")
    func groupByDateAndMetric() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        let day2 = day1.addingTimeInterval(86400) // 2023-11-15

        let points = [
            makePoint(metricType: .steps, timestamp: day1),
            makePoint(metricType: .heartRate, timestamp: day1),
            makePoint(metricType: .steps, timestamp: day2)
        ]

        let grouped = exporter.groupByDateAndMetric(points)

        #expect(grouped.count == 3)
    }

    // MARK: Full Pipeline

    @Test("mergeAndEncode with JSON format produces valid output")
    func mergeAndEncodeJSON() throws {
        let point = makePoint()
        let result = try exporter.mergeAndEncode(
            existingData: nil,
            incoming: [point],
            format: .json
        )

        #expect(result.newCount == 1)
        let decoded = exporter.decodeJSON(result.data)
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
}
