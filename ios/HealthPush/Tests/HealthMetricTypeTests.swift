import HealthKit
import Testing
@testable import HealthPush

// MARK: - HealthMetricTypeTests

struct HealthMetricTypeTests {
    // MARK: All Cases

    @Test("All cases are present")
    func allCasesCount() {
        #expect(HealthMetricType.allCases.count == 25)
    }

    // MARK: Categories

    @Test("Activity category contains expected metrics")
    func activityCategory() {
        let activityMetrics = HealthMetricType.metrics(for: .activity)
        #expect(activityMetrics.contains(.steps))
        #expect(activityMetrics.contains(.activeEnergyBurned))
        #expect(activityMetrics.contains(.distanceWalkingRunning))
        #expect(activityMetrics.contains(.flightsClimbed))
        #expect(activityMetrics.count == 9)
    }

    @Test("Body category contains expected metrics")
    func bodyCategory() {
        let bodyMetrics = HealthMetricType.metrics(for: .body)
        #expect(bodyMetrics.contains(.bodyMass))
        #expect(bodyMetrics.contains(.bodyMassIndex))
        #expect(bodyMetrics.contains(.height))
        #expect(bodyMetrics.count == 5)
    }

    @Test("Vitals category contains expected metrics")
    func vitalsCategory() {
        let vitalsMetrics = HealthMetricType.metrics(for: .vitals)
        #expect(vitalsMetrics.contains(.heartRate))
        #expect(vitalsMetrics.contains(.oxygenSaturation))
        #expect(vitalsMetrics.contains(.bloodPressureSystolic))
        #expect(vitalsMetrics.count == 8)
    }

    @Test("Sleep category contains expected metrics")
    func sleepCategory() {
        let sleepMetrics = HealthMetricType.metrics(for: .sleep)
        #expect(sleepMetrics.contains(.sleepAnalysis))
        #expect(sleepMetrics.count == 1)
    }

    @Test("Nutrition category contains expected metrics")
    func nutritionCategory() {
        let nutritionMetrics = HealthMetricType.metrics(for: .nutrition)
        #expect(nutritionMetrics.contains(.dietaryEnergyConsumed))
        #expect(nutritionMetrics.contains(.dietaryWater))
        #expect(nutritionMetrics.count == 2)
    }

    // MARK: Category Coverage

    @Test("Every metric belongs to a category")
    func allMetricsHaveCategory() {
        for metric in HealthMetricType.allCases {
            let category = metric.category
            let metricsInCategory = HealthMetricType.metrics(for: category)
            #expect(metricsInCategory.contains(metric))
        }
    }

    @Test("All categories have at least one metric")
    func allCategoriesPopulated() {
        for category in HealthMetricCategory.allCases {
            let metrics = HealthMetricType.metrics(for: category)
            #expect(!metrics.isEmpty, "Category \(category.rawValue) has no metrics")
        }
    }

    // MARK: Display Names

    @Test("All metrics have non-empty display names")
    func displayNames() {
        for metric in HealthMetricType.allCases {
            #expect(!metric.displayName.isEmpty, "\(metric.rawValue) has empty display name")
        }
    }

    @Test("All metrics have non-empty symbol names")
    func symbolNames() {
        for metric in HealthMetricType.allCases {
            #expect(!metric.symbolName.isEmpty, "\(metric.rawValue) has empty symbol name")
        }
    }

    @Test("All metrics have non-empty unit strings")
    func unitStrings() {
        for metric in HealthMetricType.allCases {
            #expect(!metric.unitString.isEmpty, "\(metric.rawValue) has empty unit string")
        }
    }

    @Test("All metrics have non-empty sensor entity suffixes")
    func sensorEntitySuffixes() {
        for metric in HealthMetricType.allCases {
            #expect(!metric.sensorEntitySuffix.isEmpty, "\(metric.rawValue) has empty sensor suffix")
        }
    }

    // MARK: HealthKit Types

    @Test("Exactly 11 metrics are cumulative")
    func cumulativeTypes() {
        let cumulative = HealthMetricType.allCases.filter(\.isCumulative)
        let expected: Set<HealthMetricType> = [
            .steps, .activeEnergyBurned, .basalEnergyBurned,
            .distanceWalkingRunning, .distanceCycling, .flightsClimbed,
            .appleExerciseTime, .appleStandTime, .appleMoveTime,
            .dietaryEnergyConsumed, .dietaryWater
        ]
        #expect(cumulative.count == 11)
        #expect(Set(cumulative) == expected)
    }

    @Test("No metric is both cumulative and category")
    func cumulativeAndCategoryMutuallyExclusive() {
        for metric in HealthMetricType.allCases {
            if metric.isCumulative {
                #expect(!metric.isCategoryType, "\(metric.rawValue) is both cumulative and category")
            }
        }
    }

    @Test("Only sleepAnalysis is a category type")
    func categoryTypes() {
        for metric in HealthMetricType.allCases {
            if metric == .sleepAnalysis {
                #expect(metric.isCategoryType)
                #expect(metric.hkCategoryType != nil)
                #expect(metric.hkQuantityType == nil)
            } else {
                #expect(!metric.isCategoryType)
                #expect(metric.hkQuantityType != nil)
                #expect(metric.hkCategoryType == nil)
            }
        }
    }

    @Test("All metrics have a valid HK sample type")
    func sampleTypes() {
        for metric in HealthMetricType.allCases {
            #expect(metric.hkSampleType != nil, "\(metric.rawValue) has nil sample type")
        }
    }

    @Test("Quantity metrics have valid HK units")
    func hkUnits() {
        for metric in HealthMetricType.allCases where !metric.isCategoryType {
            #expect(metric.hkUnit != nil, "\(metric.rawValue) has nil HK unit")
        }
    }

    // MARK: Codable

    @Test("HealthMetricType round-trips through Codable")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for metric in HealthMetricType.allCases {
            let data = try encoder.encode(metric)
            let decoded = try decoder.decode(HealthMetricType.self, from: data)
            #expect(decoded == metric)
        }
    }

    // MARK: Identifiable

    @Test("Each metric has a unique id")
    func uniqueIDs() {
        let ids = HealthMetricType.allCases.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }
}
