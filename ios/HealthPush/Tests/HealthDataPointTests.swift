import Foundation
import Testing
@testable import HealthPush

// MARK: - HealthDataPointTests

struct HealthDataPointTests {
    // MARK: Initialization

    @Test("Creates a data point with all properties")
    func initialization() {
        let id = UUID()
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(3600)

        let point = HealthDataPoint(
            id: id,
            metricType: .steps,
            value: 1234,
            unit: "count",
            startDate: startDate,
            endDate: endDate,
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            categoryValue: nil,
            aggregation: "raw"
        )

        #expect(point.id == id)
        #expect(point.metricType == .steps)
        #expect(point.value == 1234)
        #expect(point.unit == "count")
        #expect(point.startDate == startDate)
        #expect(point.endDate == endDate)
        #expect(point.sourceName == "Apple Watch")
        #expect(point.sourceBundleIdentifier == "com.apple.health")
        #expect(point.categoryValue == nil)
        #expect(point.schemaVersion == "1.0")
        #expect(point.aggregation == "raw")
        #expect(!point.deleted)
        #expect(point.deletedAt == nil)
    }

    @Test("Creates a data point with default UUID")
    func defaultUUID() {
        let point = HealthDataPoint(
            metricType: .heartRate,
            value: 72,
            unit: "count/min",
            startDate: .now,
            endDate: .now,
            sourceName: "iPhone"
        )

        #expect(point.sourceBundleIdentifier == nil)
        // Default UUID is generated
        #expect(point.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test("tzOffset defaults to current timezone")
    func tzOffsetDefault() {
        let point = HealthDataPoint(
            metricType: .heartRate,
            value: 72,
            unit: "count/min",
            startDate: .now,
            endDate: .now,
            sourceName: "iPhone"
        )

        let expected = HealthDataPoint.currentTZOffset()
        #expect(point.tzOffset == expected)
    }

    @Test("tzOffset can be set explicitly")
    func tzOffsetExplicit() {
        let point = HealthDataPoint(
            metricType: .heartRate,
            value: 72,
            unit: "count/min",
            startDate: .now,
            endDate: .now,
            sourceName: "iPhone",
            tzOffset: "-05:00"
        )

        #expect(point.tzOffset == "-05:00")
    }

    @Test("currentTZOffset produces valid format")
    func tzOffsetFormat() {
        let offset = HealthDataPoint.currentTZOffset()
        // Should match +HH:MM or -HH:MM
        let pattern = /^[+-]\d{2}:\d{2}$/
        #expect(offset.contains(pattern))
    }

    // MARK: Codable (v1 nested schema)

    @Test("Round-trips through JSON encoding and decoding with v1 nested schema")
    func codable() throws {
        let original = HealthDataPoint(
            metricType: .heartRate,
            value: 72.5,
            unit: "count/min",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_060),
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            categoryValue: 4,
            aggregation: "raw",
            tzOffset: "+01:00"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthDataPoint.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.metricType == original.metricType)
        #expect(decoded.value == original.value)
        #expect(decoded.unit == original.unit)
        #expect(decoded.sourceName == original.sourceName)
        #expect(decoded.sourceBundleIdentifier == original.sourceBundleIdentifier)
        #expect(decoded.categoryValue == 4)
        #expect(decoded.schemaVersion == "1.0")
        #expect(decoded.tzOffset == "+01:00")
        #expect(decoded.aggregation == "raw")
        #expect(!decoded.deleted)
    }

    @Test("JSON output has nested metric and source objects")
    func jsonStructure() throws {
        let point = HealthDataPoint(
            metricType: .heartRate,
            value: 72.0,
            unit: "count/min",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_060),
            sourceName: "Apple Watch",
            sourceBundleIdentifier: "com.apple.health",
            tzOffset: "+01:00"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(point)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Check nested metric
        let metric = json?["metric"] as? [String: Any]
        #expect(metric?["key"] as? String == "heart_rate")
        #expect(metric?["hkIdentifier"] as? String == "HKQuantityTypeIdentifierHeartRate")
        #expect(metric?["kind"] as? String == "quantity")

        // Check nested source
        let source = json?["source"] as? [String: Any]
        #expect(source?["name"] as? String == "Apple Watch")
        #expect(source?["bundleId"] as? String == "com.apple.health")

        // Check top-level fields
        #expect(json?["schemaVersion"] as? String == "1.0")
        #expect(json?["aggregation"] as? String == "raw")
        #expect(json?["tzOffset"] as? String == "+01:00")
    }

    // MARK: Equatable

    @Test("Two points with same properties are equal")
    func equality() {
        let id = UUID()
        let now = Date()
        let point1 = HealthDataPoint(
            id: id,
            metricType: .steps,
            value: 100,
            unit: "count",
            startDate: now,
            endDate: now,
            sourceName: "Watch",
            tzOffset: "+00:00"
        )
        let point2 = HealthDataPoint(
            id: id,
            metricType: .steps,
            value: 100,
            unit: "count",
            startDate: point1.startDate,
            endDate: point1.endDate,
            sourceName: "Watch",
            tzOffset: "+00:00"
        )

        #expect(point1 == point2)
    }

    // MARK: Aggregate ID

    @Test("aggregateID is deterministic -- same inputs produce same UUID")
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

    @Test("aggregateID includes aggregation in hash input")
    func aggregateIDIncludesAggregation() {
        let sumID = HealthDataPoint.aggregateID(date: "2026-04-05", metric: .steps, aggregation: "sum")
        let rawID = HealthDataPoint.aggregateID(date: "2026-04-05", metric: .steps, aggregation: "raw")
        #expect(sumID != rawID)
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

    // MARK: Tombstone

    @Test("Tombstone fields default correctly")
    func tombstoneDefaults() {
        let point = HealthDataPoint(
            metricType: .steps,
            value: 100,
            unit: "count",
            startDate: .now,
            endDate: .now,
            sourceName: "Watch"
        )

        #expect(!point.deleted)
        #expect(point.deletedAt == nil)
    }

    @Test("Tombstone can be created with deleted flag")
    func tombstoneCreation() {
        let now = Date()
        let point = HealthDataPoint(
            metricType: .steps,
            value: 100,
            unit: "count",
            startDate: now,
            endDate: now,
            sourceName: "Watch",
            deleted: true,
            deletedAt: now
        )

        #expect(point.deleted)
        #expect(point.deletedAt != nil)
    }
}
