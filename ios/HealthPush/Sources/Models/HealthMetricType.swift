import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - HealthMetricCategory

/// Groups health metrics into logical categories for display.
enum HealthMetricCategory: String, CaseIterable, Codable {
    case activity = "Activity"
    case body = "Body"
    case vitals = "Vitals"
    case sleep = "Sleep"
    case nutrition = "Nutrition"

    /// SF Symbol name representing this category.
    var symbolName: String {
        switch self {
        case .activity: "figure.run"
        case .body: "figure.stand"
        case .vitals: "heart.fill"
        case .sleep: "bed.double.fill"
        case .nutrition: "fork.knife"
        }
    }
}

// MARK: - HealthMetricType

/// Enumerates all supported HealthKit metrics that HealthPush can sync.
enum HealthMetricType: String, CaseIterable, Codable, Identifiable {
    // Activity
    case steps
    case activeEnergyBurned
    case basalEnergyBurned
    case distanceWalkingRunning
    case distanceCycling
    case flightsClimbed
    case appleExerciseTime
    case appleStandTime
    case appleMoveTime

    // Body
    case bodyMass
    case bodyMassIndex
    case bodyFatPercentage
    case height
    case leanBodyMass

    // Vitals
    case heartRate
    case restingHeartRate
    case heartRateVariabilitySDNN
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case oxygenSaturation
    case respiratoryRate
    case bodyTemperature

    /// Sleep
    case sleepAnalysis

    // Nutrition
    case dietaryEnergyConsumed
    case dietaryWater

    var id: String {
        rawValue
    }

    /// Human-readable display name for the metric.
    var displayName: String {
        switch self {
        case .steps: "Steps"
        case .activeEnergyBurned: "Active Energy"
        case .basalEnergyBurned: "Resting Energy"
        case .distanceWalkingRunning: "Walking + Running Distance"
        case .distanceCycling: "Cycling Distance"
        case .flightsClimbed: "Flights Climbed"
        case .appleExerciseTime: "Exercise Minutes"
        case .appleStandTime: "Stand Time"
        case .appleMoveTime: "Move Time"
        case .bodyMass: "Weight"
        case .bodyMassIndex: "BMI"
        case .bodyFatPercentage: "Body Fat"
        case .height: "Height"
        case .leanBodyMass: "Lean Body Mass"
        case .heartRate: "Heart Rate"
        case .restingHeartRate: "Resting Heart Rate"
        case .heartRateVariabilitySDNN: "Heart Rate Variability"
        case .bloodPressureSystolic: "Blood Pressure (Systolic)"
        case .bloodPressureDiastolic: "Blood Pressure (Diastolic)"
        case .oxygenSaturation: "Blood Oxygen"
        case .respiratoryRate: "Respiratory Rate"
        case .bodyTemperature: "Body Temperature"
        case .sleepAnalysis: "Sleep Analysis"
        case .dietaryEnergyConsumed: "Dietary Energy"
        case .dietaryWater: "Water Intake"
        }
    }

    /// The category this metric belongs to.
    var category: HealthMetricCategory {
        switch self {
        case .steps,
             .activeEnergyBurned,
             .basalEnergyBurned,
             .distanceWalkingRunning,
             .distanceCycling,
             .flightsClimbed,
             .appleExerciseTime,
             .appleStandTime,
             .appleMoveTime:
            .activity
        case .bodyMass,
             .bodyMassIndex,
             .bodyFatPercentage,
             .height,
             .leanBodyMass:
            .body
        case .heartRate,
             .restingHeartRate,
             .heartRateVariabilitySDNN,
             .bloodPressureSystolic,
             .bloodPressureDiastolic,
             .oxygenSaturation,
             .respiratoryRate,
             .bodyTemperature:
            .vitals
        case .sleepAnalysis:
            .sleep
        case .dietaryEnergyConsumed,
             .dietaryWater:
            .nutrition
        }
    }

    /// SF Symbol name for the metric.
    var symbolName: String {
        switch self {
        case .steps: "figure.walk"
        case .activeEnergyBurned: "flame.fill"
        case .basalEnergyBurned: "flame"
        case .distanceWalkingRunning: "figure.walk.motion"
        case .distanceCycling: "bicycle"
        case .flightsClimbed: "stairs"
        case .appleExerciseTime: "figure.run"
        case .appleStandTime: "figure.stand"
        case .appleMoveTime: "figure.walk"
        case .bodyMass: "scalemass.fill"
        case .bodyMassIndex: "number.square.fill"
        case .bodyFatPercentage: "percent"
        case .height: "ruler.fill"
        case .leanBodyMass: "figure.strengthtraining.traditional"
        case .heartRate: "heart.fill"
        case .restingHeartRate: "heart.text.square.fill"
        case .heartRateVariabilitySDNN: "waveform.path.ecg"
        case .bloodPressureSystolic: "arrow.up.heart.fill"
        case .bloodPressureDiastolic: "arrow.down.heart.fill"
        case .oxygenSaturation: "lungs.fill"
        case .respiratoryRate: "wind"
        case .bodyTemperature: "thermometer.medium"
        case .sleepAnalysis: "bed.double.fill"
        case .dietaryEnergyConsumed: "fork.knife"
        case .dietaryWater: "drop.fill"
        }
    }

    /// The default unit string for this metric.
    var unitString: String {
        switch self {
        case .steps: "count"
        case .activeEnergyBurned,
             .basalEnergyBurned,
             .dietaryEnergyConsumed: "kcal"
        case .distanceWalkingRunning,
             .distanceCycling: "km"
        case .flightsClimbed: "count"
        case .appleExerciseTime,
             .appleStandTime,
             .appleMoveTime: "min"
        case .bodyMass,
             .leanBodyMass: "kg"
        case .bodyMassIndex: "count"
        case .bodyFatPercentage: "%"
        case .height: "cm"
        case .heartRate,
             .restingHeartRate: "bpm"
        case .heartRateVariabilitySDNN: "ms"
        case .bloodPressureSystolic,
             .bloodPressureDiastolic: "mmHg"
        case .oxygenSaturation: "%"
        case .respiratoryRate: "breaths/min"
        case .bodyTemperature: "degC"
        case .sleepAnalysis: "hr"
        case .dietaryWater: "mL"
        }
    }

    /// A snake_case identifier for this metric used in file names and entity IDs.
    var fileStem: String {
        switch self {
        case .steps: "steps"
        case .activeEnergyBurned: "active_energy"
        case .basalEnergyBurned: "resting_energy"
        case .distanceWalkingRunning: "walking_running_distance"
        case .distanceCycling: "cycling_distance"
        case .flightsClimbed: "flights_climbed"
        case .appleExerciseTime: "exercise_minutes"
        case .appleStandTime: "stand_time"
        case .appleMoveTime: "move_time"
        case .bodyMass: "weight"
        case .bodyMassIndex: "bmi"
        case .bodyFatPercentage: "body_fat"
        case .height: "height"
        case .leanBodyMass: "lean_body_mass"
        case .heartRate: "heart_rate"
        case .restingHeartRate: "resting_heart_rate"
        case .heartRateVariabilitySDNN: "hrv"
        case .bloodPressureSystolic: "blood_pressure_systolic"
        case .bloodPressureDiastolic: "blood_pressure_diastolic"
        case .oxygenSaturation: "blood_oxygen"
        case .respiratoryRate: "respiratory_rate"
        case .bodyTemperature: "body_temperature"
        case .sleepAnalysis: "sleep"
        case .dietaryEnergyConsumed: "dietary_energy"
        case .dietaryWater: "water_intake"
        }
    }

    /// Whether this metric is a category type (vs quantity type).
    var isCategoryType: Bool {
        switch self {
        case .sleepAnalysis: true
        default: false
        }
    }

    /// Whether this metric uses cumulative aggregation in HealthKit.
    ///
    /// Cumulative metrics (steps, energy, distance, etc.) overlap across sources
    /// (iPhone + Watch both count steps). These must be queried via
    /// `HKStatisticsCollectionQuery` with `.cumulativeSum` to get Apple's
    /// deduplicated totals. Discrete metrics have no overlap risk.
    var isCumulative: Bool {
        switch self {
        case .steps,
             .activeEnergyBurned,
             .basalEnergyBurned,
             .distanceWalkingRunning,
             .distanceCycling,
             .flightsClimbed,
             .appleExerciseTime,
             .appleStandTime,
             .appleMoveTime,
             .dietaryEnergyConsumed,
             .dietaryWater:
            true
        default:
            false
        }
    }

    /// Returns all metrics in a given category.
    static func metrics(for category: HealthMetricCategory) -> [HealthMetricType] {
        allCases.filter { $0.category == category }
    }
}

#if canImport(HealthKit)
extension HealthMetricType {
    /// The corresponding HealthKit sample type.
    var hkSampleType: HKSampleType? {
        if isCategoryType {
            hkCategoryType
        } else {
            hkQuantityType
        }
    }

    /// The corresponding HKQuantityType, if applicable.
    var hkQuantityType: HKQuantityType? {
        guard let identifier = hkQuantityTypeIdentifier else { return nil }
        return HKQuantityType(identifier)
    }

    /// The corresponding HKCategoryType, if applicable.
    var hkCategoryType: HKCategoryType? {
        guard let identifier = hkCategoryTypeIdentifier else { return nil }
        return HKCategoryType(identifier)
    }

    /// The HKQuantityTypeIdentifier for quantity-based metrics.
    var hkQuantityTypeIdentifier: HKQuantityTypeIdentifier? {
        switch self {
        case .steps: .stepCount
        case .activeEnergyBurned: .activeEnergyBurned
        case .basalEnergyBurned: .basalEnergyBurned
        case .distanceWalkingRunning: .distanceWalkingRunning
        case .distanceCycling: .distanceCycling
        case .flightsClimbed: .flightsClimbed
        case .appleExerciseTime: .appleExerciseTime
        case .appleStandTime: .appleStandTime
        case .appleMoveTime: .appleMoveTime
        case .bodyMass: .bodyMass
        case .bodyMassIndex: .bodyMassIndex
        case .bodyFatPercentage: .bodyFatPercentage
        case .height: .height
        case .leanBodyMass: .leanBodyMass
        case .heartRate: .heartRate
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariabilitySDNN: .heartRateVariabilitySDNN
        case .bloodPressureSystolic: .bloodPressureSystolic
        case .bloodPressureDiastolic: .bloodPressureDiastolic
        case .oxygenSaturation: .oxygenSaturation
        case .respiratoryRate: .respiratoryRate
        case .bodyTemperature: .bodyTemperature
        case .dietaryEnergyConsumed: .dietaryEnergyConsumed
        case .dietaryWater: .dietaryWater
        case .sleepAnalysis: nil
        }
    }

    /// The HKCategoryTypeIdentifier for category-based metrics.
    var hkCategoryTypeIdentifier: HKCategoryTypeIdentifier? {
        switch self {
        case .sleepAnalysis: .sleepAnalysis
        default: nil
        }
    }

    /// The HKUnit used to query this metric.
    var hkUnit: HKUnit? {
        switch self {
        case .steps: .count()
        case .activeEnergyBurned,
             .basalEnergyBurned,
             .dietaryEnergyConsumed: .kilocalorie()
        case .distanceWalkingRunning,
             .distanceCycling: .meterUnit(with: .kilo)
        case .flightsClimbed: .count()
        case .appleExerciseTime,
             .appleStandTime,
             .appleMoveTime: .minute()
        case .bodyMass,
             .leanBodyMass: .gramUnit(with: .kilo)
        case .bodyMassIndex: .count()
        case .bodyFatPercentage: .percent()
        case .height: .meterUnit(with: .centi)
        case .heartRate,
             .restingHeartRate:
            .count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN: .secondUnit(with: .milli)
        case .bloodPressureSystolic,
             .bloodPressureDiastolic: .millimeterOfMercury()
        case .oxygenSaturation: .percent()
        case .respiratoryRate: .count().unitDivided(by: .minute())
        case .bodyTemperature: .degreeCelsius()
        case .dietaryWater: .literUnit(with: .milli)
        case .sleepAnalysis: nil
        }
    }
}
#endif
