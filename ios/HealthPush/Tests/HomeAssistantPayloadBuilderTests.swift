import Foundation
import HealthKit
import Testing
@testable import HealthPush

// MARK: - HomeAssistantPayloadBuilderTests

@Suite("HomeAssistantPayloadBuilder")
struct HomeAssistantPayloadBuilderTests {
    // MARK: Helpers

    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func makePoint(
        id: UUID = UUID(),
        metricType: HealthMetricType = .heartRate,
        value: Double = 72.0,
        startDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endDate: Date? = nil,
        categoryValue: Int? = nil
    ) -> HealthDataPoint {
        HealthDataPoint(
            id: id,
            metricType: metricType,
            value: value,
            unit: metricType.canonicalUnit,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(60),
            sourceName: "Test Device",
            categoryValue: categoryValue
        )
    }

    // MARK: Single Metric Payload Shape

    @Test("Heart rate payload has expected keys and values")
    func heartRatePayloadShape() {
        let point = makePoint(metricType: .heartRate, value: 72.0)
        let payload = HomeAssistantPayloadBuilder.metricPayload(for: point, formatter: formatter)

        #expect(payload["type"] as? String == "heart_rate")
        #expect(payload["value"] as? Double == 72.0)
        #expect(payload["unit"] as? String == "bpm")
        #expect(payload["id"] as? String == point.id.uuidString)
        #expect(payload["start_date"] as? String != nil)
        #expect(payload["end_date"] as? String != nil)
    }

    @Test("Steps payload uses integer value")
    func stepsPayloadUsesInteger() {
        let point = makePoint(metricType: .steps, value: 8432.0)
        let payload = HomeAssistantPayloadBuilder.metricPayload(for: point, formatter: formatter)

        #expect(payload["type"] as? String == "steps")
        #expect(payload["value"] as? Int == 8432)
        #expect(payload["unit"] as? String == "steps")
    }

    @Test("Flights climbed payload uses integer value")
    func flightsClimbedUsesInteger() {
        let point = makePoint(metricType: .flightsClimbed, value: 12.0)
        let payload = HomeAssistantPayloadBuilder.metricPayload(for: point, formatter: formatter)

        #expect(payload["type"] as? String == "flights_climbed")
        #expect(payload["value"] as? Int == 12)
    }

    @Test("Body fat percentage is multiplied by 100")
    func bodyFatPercentageMultiplied() {
        let point = makePoint(metricType: .bodyFatPercentage, value: 0.185)
        let payload = HomeAssistantPayloadBuilder.metricPayload(for: point, formatter: formatter)

        #expect(payload["type"] as? String == "body_fat")
        #expect(payload["value"] as? Double == 18.5)
        #expect(payload["unit"] as? String == "%")
    }

    @Test("Blood oxygen (SpO2) is multiplied by 100")
    func oxygenSaturationMultiplied() {
        let point = makePoint(metricType: .oxygenSaturation, value: 0.98)
        let payload = HomeAssistantPayloadBuilder.metricPayload(for: point, formatter: formatter)

        #expect(payload["type"] as? String == "blood_oxygen")
        #expect(payload["value"] as? Double == 98.0)
        #expect(payload["unit"] as? String == "%")
    }

    @Test("Weight payload uses two-decimal rounding")
    func weightPayloadRounding() {
        let point = makePoint(metricType: .bodyMass, value: 75.456)
        let payload = HomeAssistantPayloadBuilder.metricPayload(for: point, formatter: formatter)

        #expect(payload["type"] as? String == "weight")
        #expect(payload["value"] as? Double == 75.46)
    }

    // MARK: buildMetricPayloads

    @Test("buildMetricPayloads filters to enabled metrics only")
    func filtersToEnabledMetrics() {
        let points = [
            makePoint(metricType: .heartRate, value: 72.0),
            makePoint(metricType: .steps, value: 5000.0),
            makePoint(metricType: .bodyMass, value: 80.0)
        ]
        let enabled: Set<HealthMetricType> = [.heartRate, .steps]

        let payloads = HomeAssistantPayloadBuilder.buildMetricPayloads(
            from: points,
            enabledMetrics: enabled,
            formatter: formatter
        )

        let types = Set(payloads.compactMap { $0["type"] as? String })
        #expect(types.contains("heart_rate"))
        #expect(types.contains("steps"))
        #expect(!types.contains("weight"))
        #expect(payloads.count == 2)
    }

    @Test("buildMetricPayloads selects latest data point per metric")
    func selectsLatestPerMetric() {
        let older = makePoint(
            metricType: .heartRate,
            value: 60.0,
            startDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = makePoint(
            metricType: .heartRate,
            value: 80.0,
            startDate: Date(timeIntervalSince1970: 1_700_003_600)
        )

        let payloads = HomeAssistantPayloadBuilder.buildMetricPayloads(
            from: [older, newer],
            enabledMetrics: [.heartRate],
            formatter: formatter
        )

        #expect(payloads.count == 1)
        #expect(payloads[0]["value"] as? Double == 80.0)
    }

    @Test("buildMetricPayloads returns empty array for empty data")
    func emptyDataReturnsEmpty() {
        let payloads = HomeAssistantPayloadBuilder.buildMetricPayloads(
            from: [],
            enabledMetrics: [.heartRate],
            formatter: formatter
        )
        #expect(payloads.isEmpty)
    }

    @Test("buildMetricPayloads sorts output by type name")
    func outputSortedByType() {
        let points = [
            makePoint(metricType: .bodyMass, value: 80.0),
            makePoint(metricType: .heartRate, value: 72.0),
            makePoint(metricType: .steps, value: 5000.0)
        ]

        let payloads = HomeAssistantPayloadBuilder.buildMetricPayloads(
            from: points,
            enabledMetrics: [.bodyMass, .heartRate, .steps],
            formatter: formatter
        )

        let types = payloads.compactMap { $0["type"] as? String }
        #expect(types == types.sorted())
    }

    // MARK: Sleep Aggregation

    @Test("Sleep payload merges overlapping asleep intervals")
    func sleepMergesOverlapping() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            makePoint(
                metricType: .sleepAnalysis,
                value: 5400,
                startDate: start,
                endDate: start.addingTimeInterval(90 * 60),
                categoryValue: HKCategoryValueSleepAnalysis.asleepCore.rawValue
            ),
            makePoint(
                metricType: .sleepAnalysis,
                value: 5400,
                startDate: start.addingTimeInterval(60 * 60),
                endDate: start.addingTimeInterval(150 * 60),
                categoryValue: HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ),
            makePoint(
                metricType: .sleepAnalysis,
                value: 23400,
                startDate: start.addingTimeInterval(150 * 60),
                endDate: start.addingTimeInterval(540 * 60),
                categoryValue: HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            )
        ]

        let payload = HomeAssistantPayloadBuilder.sleepPayload(from: points, formatter: formatter)

        #expect(payload != nil)
        #expect(payload?["type"] as? String == "sleep")
        #expect(payload?["value"] as? Double == 9.0)
        #expect(payload?["unit"] as? String == "hr")
    }

    @Test("Sleep payload ignores in-bed samples")
    func sleepIgnoresInBed() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            makePoint(
                metricType: .sleepAnalysis,
                value: 7200,
                startDate: start,
                endDate: start.addingTimeInterval(120 * 60),
                categoryValue: HKCategoryValueSleepAnalysis.asleepCore.rawValue
            ),
            makePoint(
                metricType: .sleepAnalysis,
                value: 36000,
                startDate: start.addingTimeInterval(-60 * 60),
                endDate: start.addingTimeInterval(540 * 60),
                categoryValue: HKCategoryValueSleepAnalysis.inBed.rawValue
            )
        ]

        let payload = HomeAssistantPayloadBuilder.sleepPayload(from: points, formatter: formatter)

        #expect(payload != nil)
        // Only the 2hr core sleep should count, not the 10hr in-bed
        #expect(payload?["value"] as? Double == 2.0)
    }

    @Test("Sleep payload returns nil when no asleep samples exist")
    func sleepNilWithNoAsleep() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            makePoint(
                metricType: .sleepAnalysis,
                value: 36000,
                startDate: start,
                endDate: start.addingTimeInterval(600 * 60),
                categoryValue: HKCategoryValueSleepAnalysis.inBed.rawValue
            )
        ]

        let payload = HomeAssistantPayloadBuilder.sleepPayload(from: points, formatter: formatter)
        #expect(payload == nil)
    }

    @Test("Sleep payload returns nil for empty input")
    func sleepNilForEmpty() {
        let payload = HomeAssistantPayloadBuilder.sleepPayload(from: [], formatter: formatter)
        #expect(payload == nil)
    }

    // MARK: mergedSleepIntervals

    @Test("Merged intervals collapse fully overlapping intervals")
    func mergedIntervalsFullOverlap() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            makePoint(
                metricType: .sleepAnalysis,
                value: 3600,
                startDate: start,
                endDate: start.addingTimeInterval(3600),
                categoryValue: HKCategoryValueSleepAnalysis.asleepCore.rawValue
            ),
            makePoint(
                metricType: .sleepAnalysis,
                value: 1800,
                startDate: start.addingTimeInterval(900),
                endDate: start.addingTimeInterval(2700),
                categoryValue: HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            )
        ]

        let intervals = HomeAssistantPayloadBuilder.mergedSleepIntervals(from: points)
        #expect(intervals.count == 1)
        #expect(intervals[0].start == start)
        #expect(intervals[0].end == start.addingTimeInterval(3600))
    }

    @Test("Merged intervals keep non-overlapping intervals separate")
    func mergedIntervalsNonOverlapping() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let gap = start.addingTimeInterval(7200) // 2hr gap
        let points = [
            makePoint(
                metricType: .sleepAnalysis,
                value: 3600,
                startDate: start,
                endDate: start.addingTimeInterval(3600),
                categoryValue: HKCategoryValueSleepAnalysis.asleepCore.rawValue
            ),
            makePoint(
                metricType: .sleepAnalysis,
                value: 3600,
                startDate: gap,
                endDate: gap.addingTimeInterval(3600),
                categoryValue: HKCategoryValueSleepAnalysis.asleepREM.rawValue
            )
        ]

        let intervals = HomeAssistantPayloadBuilder.mergedSleepIntervals(from: points)
        #expect(intervals.count == 2)
    }

    // MARK: isAsleepSample

    @Test("isAsleepSample accepts all asleep categories")
    func isAsleepAcceptsAllAsleep() {
        let asleepValues = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        for value in asleepValues {
            let point = makePoint(metricType: .sleepAnalysis, categoryValue: value)
            #expect(HomeAssistantPayloadBuilder.isAsleepSample(point))
        }
    }

    @Test("isAsleepSample rejects in-bed and awake")
    func isAsleepRejectsNonAsleep() {
        let nonAsleepValues = [
            HKCategoryValueSleepAnalysis.inBed.rawValue,
            HKCategoryValueSleepAnalysis.awake.rawValue
        ]

        for value in nonAsleepValues {
            let point = makePoint(metricType: .sleepAnalysis, categoryValue: value)
            #expect(!HomeAssistantPayloadBuilder.isAsleepSample(point))
        }
    }

    @Test("isAsleepSample returns true for non-sleep metrics")
    func isAsleepTrueForNonSleep() {
        let point = makePoint(metricType: .heartRate)
        #expect(HomeAssistantPayloadBuilder.isAsleepSample(point))
    }

    @Test("isAsleepSample returns true when categoryValue is nil")
    func isAsleepTrueWhenNilCategory() {
        let point = makePoint(metricType: .sleepAnalysis, categoryValue: nil)
        #expect(HomeAssistantPayloadBuilder.isAsleepSample(point))
    }
}
