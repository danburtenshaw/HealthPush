import Foundation
import Testing
@testable import HealthPush

// MARK: - HealthDataPointTests

struct HealthDataPointTests {
    // MARK: Initialization

    @Test("Creates a data point with all properties")
    func initialization() {
        let id = UUID()
        let timestamp = Date()
        let endTimestamp = timestamp.addingTimeInterval(3600)

        let point = HealthDataPoint(
            id: id,
            metricType: .steps,
            value: 1234,
            unit: "count",
            timestamp: timestamp,
            endTimestamp: endTimestamp,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            categoryValue: nil
        )

        #expect(point.id == id)
        #expect(point.metricType == .steps)
        #expect(point.value == 1234)
        #expect(point.unit == "count")
        #expect(point.timestamp == timestamp)
        #expect(point.endTimestamp == endTimestamp)
        #expect(point.sourceName == "Apple Watch")
        #expect(point.sourceBundleIdentifier == "com.apple.health")
        #expect(point.categoryValue == nil)
    }

    @Test("Creates a data point with default UUID")
    func defaultUUID() {
        let point = HealthDataPoint(
            metricType: .heartRate,
            value: 72,
            unit: "bpm",
            timestamp: .now,
            endTimestamp: .now,
            sourceName: "iPhone"
        )

        #expect(point.sourceBundleIdentifier == nil)
        // Default UUID is generated
        #expect(point.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    // MARK: Codable

    @Test("Round-trips through JSON encoding and decoding")
    func codable() throws {
        let original = HealthDataPoint(
            metricType: .heartRate,
            value: 72.5,
            unit: "bpm",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            endTimestamp: Date(timeIntervalSince1970: 1_700_000_060),
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            categoryValue: 4
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HealthDataPoint.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.metricType == original.metricType)
        #expect(decoded.value == original.value)
        #expect(decoded.unit == original.unit)
        #expect(decoded.sourceName == original.sourceName)
        #expect(decoded.sourceBundleIdentifier == original.sourceBundleIdentifier)
        #expect(decoded.categoryValue == 4)
    }

    // MARK: Equatable

    @Test("Two points with same ID are equal")
    func equality() {
        let id = UUID()
        let point1 = HealthDataPoint(
            id: id,
            metricType: .steps,
            value: 100,
            unit: "count",
            timestamp: .now,
            endTimestamp: .now,
            sourceName: "Watch"
        )
        let point2 = HealthDataPoint(
            id: id,
            metricType: .steps,
            value: 100,
            unit: "count",
            timestamp: point1.timestamp,
            endTimestamp: point1.endTimestamp,
            sourceName: "Watch"
        )

        #expect(point1 == point2)
    }

    // MARK: Aggregate ID

    @Test("aggregateID is deterministic — same inputs produce same UUID")
    func aggregateIDDeterministic() {
        let id1 = HealthDataPoint.aggregateID(date: "2026-04-05", metric: .steps)
        let id2 = HealthDataPoint.aggregateID(date: "2026-04-05", metric: .steps)
        #expect(id1 == id2)
    }

    @Test("aggregateID differs for different dates")
    func aggregateIDDifferentDates() {
        let id1 = HealthDataPoint.aggregateID(date: "2026-04-05", metric: .steps)
        let id2 = HealthDataPoint.aggregateID(date: "2026-04-06", metric: .steps)
        #expect(id1 != id2)
    }

    @Test("aggregateID differs for different metrics")
    func aggregateIDDifferentMetrics() {
        let id1 = HealthDataPoint.aggregateID(date: "2026-04-05", metric: .steps)
        let id2 = HealthDataPoint.aggregateID(date: "2026-04-05", metric: .activeEnergyBurned)
        #expect(id1 != id2)
    }

    @Test("aggregateID has correct UUID version 5 bits")
    func aggregateIDVersionBits() throws {
        let id = HealthDataPoint.aggregateID(date: "2026-04-05", metric: .steps)
        let uuidString = id.uuidString
        // Version nibble is character at index 14 (0-indexed in the hyphen-stripped form)
        // In UUID string format: xxxxxxxx-xxxx-Vxxx-Nxxx-xxxxxxxxxxxx
        // V should be 5, N should be 8, 9, a, or b
        let parts = uuidString.split(separator: "-")
        let versionChar = try #require(parts[2].first)
        #expect(versionChar == "5")

        let variantChar = try #require(parts[3].first)
        #expect("89AB".contains(variantChar.uppercased()))
    }
}
