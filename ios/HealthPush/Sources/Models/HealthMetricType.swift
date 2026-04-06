import Foundation
import HealthKit

// MARK: - HealthMetricCategory

/// Groups health metrics into logical categories for display.
enum HealthMetricCategory: String, CaseIterable, Codable, Sendable {
    case activity = "Activity"
    case body = "Body"
    case vitals = "Vitals"
    case sleep = "Sleep"
    case nutrition = "Nutrition"

    /// SF Symbol name representing this category.
    var symbolName: String {
        switch self {
        case .activity: return "figure.run"
        case .body: return "figure.stand"
        case .vitals: return "heart.fill"
        case .sleep: return "bed.double.fill"
        case .nutrition: return "fork.knife"
        }
    }
}

// MARK: - HealthMetricType

/// Enumerates all supported HealthKit metrics that HealthPush can sync.
enum HealthMetricType: String, CaseIterable, Codable, Sendable, Identifiable {
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

    // Sleep
    case sleepAnalysis

    // Nutrition
    case dietaryEnergyConsumed
    case dietaryWater

    var id: String { rawValue }

    /// Human-readable display name for the metric.
    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergyBurned: return "Active Energy"
        case .basalEnergyBurned: return "Resting Energy"
        case .distanceWalkingRunning: return "Walking + Running Distance"
        case .distanceCycling: return "Cycling Distance"
        case .flightsClimbed: return "Flights Climbed"
        case .appleExerciseTime: return "Exercise Minutes"
        case .appleStandTime: return "Stand Time"
        case .appleMoveTime: return "Move Time"
        case .bodyMass: return "Weight"
        case .bodyMassIndex: return "BMI"
        case .bodyFatPercentage: return "Body Fat"
        case .height: return "Height"
        case .leanBodyMass: return "Lean Body Mass"
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .heartRateVariabilitySDNN: return "Heart Rate Variability"
        case .bloodPressureSystolic: return "Blood Pressure (Systolic)"
        case .bloodPressureDiastolic: return "Blood Pressure (Diastolic)"
        case .oxygenSaturation: return "Blood Oxygen"
        case .respiratoryRate: return "Respiratory Rate"
        case .bodyTemperature: return "Body Temperature"
        case .sleepAnalysis: return "Sleep Analysis"
        case .dietaryEnergyConsumed: return "Dietary Energy"
        case .dietaryWater: return "Water Intake"
        }
    }

    /// The category this metric belongs to.
    var category: HealthMetricCategory {
        switch self {
        case .steps, .activeEnergyBurned, .basalEnergyBurned,
             .distanceWalkingRunning, .distanceCycling, .flightsClimbed,
             .appleExerciseTime, .appleStandTime, .appleMoveTime:
            return .activity
        case .bodyMass, .bodyMassIndex, .bodyFatPercentage,
             .height, .leanBodyMass:
            return .body
        case .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
             .bloodPressureSystolic, .bloodPressureDiastolic,
             .oxygenSaturation, .respiratoryRate, .bodyTemperature:
            return .vitals
        case .sleepAnalysis:
            return .sleep
        case .dietaryEnergyConsumed, .dietaryWater:
            return .nutrition
        }
    }

    /// SF Symbol name for the metric.
    var symbolName: String {
        switch self {
        case .steps: return "figure.walk"
        case .activeEnergyBurned: return "flame.fill"
        case .basalEnergyBurned: return "flame"
        case .distanceWalkingRunning: return "figure.walk.motion"
        case .distanceCycling: return "bicycle"
        case .flightsClimbed: return "stairs"
        case .appleExerciseTime: return "figure.run"
        case .appleStandTime: return "figure.stand"
        case .appleMoveTime: return "figure.walk"
        case .bodyMass: return "scalemass.fill"
        case .bodyMassIndex: return "number.square.fill"
        case .bodyFatPercentage: return "percent"
        case .height: return "ruler.fill"
        case .leanBodyMass: return "figure.strengthtraining.traditional"
        case .heartRate: return "heart.fill"
        case .restingHeartRate: return "heart.text.square.fill"
        case .heartRateVariabilitySDNN: return "waveform.path.ecg"
        case .bloodPressureSystolic: return "arrow.up.heart.fill"
        case .bloodPressureDiastolic: return "arrow.down.heart.fill"
        case .oxygenSaturation: return "lungs.fill"
        case .respiratoryRate: return "wind"
        case .bodyTemperature: return "thermometer.medium"
        case .sleepAnalysis: return "bed.double.fill"
        case .dietaryEnergyConsumed: return "fork.knife"
        case .dietaryWater: return "drop.fill"
        }
    }

    /// The default unit string for this metric.
    var unitString: String {
        switch self {
        case .steps: return "count"
        case .activeEnergyBurned, .basalEnergyBurned, .dietaryEnergyConsumed: return "kcal"
        case .distanceWalkingRunning, .distanceCycling: return "km"
        case .flightsClimbed: return "count"
        case .appleExerciseTime, .appleStandTime, .appleMoveTime: return "min"
        case .bodyMass, .leanBodyMass: return "kg"
        case .bodyMassIndex: return "count"
        case .bodyFatPercentage: return "%"
        case .height: return "cm"
        case .heartRate, .restingHeartRate: return "bpm"
        case .heartRateVariabilitySDNN: return "ms"
        case .bloodPressureSystolic, .bloodPressureDiastolic: return "mmHg"
        case .oxygenSaturation: return "%"
        case .respiratoryRate: return "breaths/min"
        case .bodyTemperature: return "degC"
        case .sleepAnalysis: return "hr"
        case .dietaryWater: return "mL"
        }
    }

    /// The Home Assistant sensor entity ID suffix.
    var sensorEntitySuffix: String {
        switch self {
        case .steps: return "steps"
        case .activeEnergyBurned: return "active_energy"
        case .basalEnergyBurned: return "resting_energy"
        case .distanceWalkingRunning: return "walking_running_distance"
        case .distanceCycling: return "cycling_distance"
        case .flightsClimbed: return "flights_climbed"
        case .appleExerciseTime: return "exercise_minutes"
        case .appleStandTime: return "stand_time"
        case .appleMoveTime: return "move_time"
        case .bodyMass: return "weight"
        case .bodyMassIndex: return "bmi"
        case .bodyFatPercentage: return "body_fat"
        case .height: return "height"
        case .leanBodyMass: return "lean_body_mass"
        case .heartRate: return "heart_rate"
        case .restingHeartRate: return "resting_heart_rate"
        case .heartRateVariabilitySDNN: return "hrv"
        case .bloodPressureSystolic: return "blood_pressure_systolic"
        case .bloodPressureDiastolic: return "blood_pressure_diastolic"
        case .oxygenSaturation: return "blood_oxygen"
        case .respiratoryRate: return "respiratory_rate"
        case .bodyTemperature: return "body_temperature"
        case .sleepAnalysis: return "sleep"
        case .dietaryEnergyConsumed: return "dietary_energy"
        case .dietaryWater: return "water_intake"
        }
    }

    /// Whether this metric is a category type (vs quantity type).
    var isCategoryType: Bool {
        switch self {
        case .sleepAnalysis: return true
        default: return false
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
        case .steps, .activeEnergyBurned, .basalEnergyBurned,
             .distanceWalkingRunning, .distanceCycling, .flightsClimbed,
             .appleExerciseTime, .appleStandTime, .appleMoveTime,
             .dietaryEnergyConsumed, .dietaryWater:
            return true
        default:
            return false
        }
    }

    /// The corresponding HealthKit sample type.
    var hkSampleType: HKSampleType? {
        if isCategoryType {
            return hkCategoryType
        } else {
            return hkQuantityType
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
        case .steps: return .stepCount
        case .activeEnergyBurned: return .activeEnergyBurned
        case .basalEnergyBurned: return .basalEnergyBurned
        case .distanceWalkingRunning: return .distanceWalkingRunning
        case .distanceCycling: return .distanceCycling
        case .flightsClimbed: return .flightsClimbed
        case .appleExerciseTime: return .appleExerciseTime
        case .appleStandTime: return .appleStandTime
        case .appleMoveTime: return .appleMoveTime
        case .bodyMass: return .bodyMass
        case .bodyMassIndex: return .bodyMassIndex
        case .bodyFatPercentage: return .bodyFatPercentage
        case .height: return .height
        case .leanBodyMass: return .leanBodyMass
        case .heartRate: return .heartRate
        case .restingHeartRate: return .restingHeartRate
        case .heartRateVariabilitySDNN: return .heartRateVariabilitySDNN
        case .bloodPressureSystolic: return .bloodPressureSystolic
        case .bloodPressureDiastolic: return .bloodPressureDiastolic
        case .oxygenSaturation: return .oxygenSaturation
        case .respiratoryRate: return .respiratoryRate
        case .bodyTemperature: return .bodyTemperature
        case .dietaryEnergyConsumed: return .dietaryEnergyConsumed
        case .dietaryWater: return .dietaryWater
        case .sleepAnalysis: return nil
        }
    }

    /// The HKCategoryTypeIdentifier for category-based metrics.
    var hkCategoryTypeIdentifier: HKCategoryTypeIdentifier? {
        switch self {
        case .sleepAnalysis: return .sleepAnalysis
        default: return nil
        }
    }

    /// The HKUnit used to query this metric.
    var hkUnit: HKUnit? {
        switch self {
        case .steps: return .count()
        case .activeEnergyBurned, .basalEnergyBurned, .dietaryEnergyConsumed: return .kilocalorie()
        case .distanceWalkingRunning, .distanceCycling: return .meterUnit(with: .kilo)
        case .flightsClimbed: return .count()
        case .appleExerciseTime, .appleStandTime, .appleMoveTime: return .minute()
        case .bodyMass, .leanBodyMass: return .gramUnit(with: .kilo)
        case .bodyMassIndex: return .count()
        case .bodyFatPercentage: return .percent()
        case .height: return .meterUnit(with: .centi)
        case .heartRate, .restingHeartRate:
            return .count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN: return .secondUnit(with: .milli)
        case .bloodPressureSystolic, .bloodPressureDiastolic: return .millimeterOfMercury()
        case .oxygenSaturation: return .percent()
        case .respiratoryRate: return .count().unitDivided(by: .minute())
        case .bodyTemperature: return .degreeCelsius()
        case .dietaryWater: return .literUnit(with: .milli)
        case .sleepAnalysis: return nil
        }
    }

    /// Returns all metrics in a given category.
    static func metrics(for category: HealthMetricCategory) -> [HealthMetricType] {
        allCases.filter { $0.category == category }
    }
}
