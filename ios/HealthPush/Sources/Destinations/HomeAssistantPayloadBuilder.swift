import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - HomeAssistantPayloadBuilder

/// Builds Home Assistant webhook payloads from health data points.
///
/// This struct encapsulates the static payload-shaping logic that was originally
/// embedded in ``HomeAssistantDestination``. Extracting it makes the logic
/// independently testable without network dependencies.
struct HomeAssistantPayloadBuilder {
    // MARK: - Metric Payloads

    /// Builds an array of metric payloads from health data points.
    ///
    /// Groups data by metric type, picks the latest value per metric,
    /// and formats each as a dictionary ready for JSON serialization.
    ///
    /// - Parameters:
    ///   - data: All health data points to include.
    ///   - enabledMetrics: The set of metrics the user has enabled.
    ///   - formatter: An ISO 8601 date formatter.
    /// - Returns: An array of dictionaries, one per metric, sorted by type name.
    static func buildMetricPayloads(
        from data: [HealthDataPoint],
        enabledMetrics: Set<HealthMetricType>,
        formatter: ISO8601DateFormatter
    ) -> [[String: Any]] {
        let grouped = Dictionary(grouping: data) { $0.metricType }
        var metrics: [[String: Any]] = []

        for (metricType, points) in grouped {
            guard enabledMetrics.contains(metricType) else { continue }

            if metricType == .sleepAnalysis {
                if let sleepPayload = sleepPayload(from: points, formatter: formatter) {
                    metrics.append(sleepPayload)
                }
                continue
            }

            guard let latest = points.max(by: { $0.startDate < $1.startDate }) else { continue }
            metrics.append(metricPayload(for: latest, formatter: formatter))
        }

        return metrics.sorted {
            ($0["type"] as? String ?? "") < ($1["type"] as? String ?? "")
        }
    }

    // MARK: - Sleep Aggregation

    /// Builds a single sleep payload from sleep analysis data points.
    ///
    /// Filters to only asleep samples (core, deep, REM, unspecified),
    /// merges overlapping intervals, and computes total sleep hours.
    ///
    /// - Parameters:
    ///   - points: Sleep analysis data points (may include in-bed, awake, etc.).
    ///   - formatter: An ISO 8601 date formatter.
    /// - Returns: A dictionary payload, or nil if no asleep intervals are found.
    static func sleepPayload(
        from points: [HealthDataPoint],
        formatter: ISO8601DateFormatter
    ) -> [String: Any]? {
        let asleepIntervals = mergedSleepIntervals(from: points)
        guard let firstInterval = asleepIntervals.first,
              let lastInterval = asleepIntervals.last
        else {
            return nil
        }

        let totalHours = asleepIntervals.reduce(0.0) { partialResult, interval in
            partialResult + interval.end.timeIntervalSince(interval.start) / 3600.0
        }

        let dateString = sleepAggregateDateFormatter.string(from: lastInterval.end)
        let aggregateID = HealthDataPoint.aggregateID(date: dateString, metric: .sleepAnalysis)

        return [
            "id": aggregateID.uuidString,
            "type": HealthMetricType.sleepAnalysis.fileStem,
            "value": (totalHours * 100).rounded() / 100,
            "unit": HealthMetricType.sleepAnalysis.displayUnit,
            "start_date": formatter.string(from: firstInterval.start),
            "end_date": formatter.string(from: lastInterval.end)
        ]
    }

    /// Merges overlapping sleep intervals into non-overlapping ranges.
    ///
    /// Only includes samples classified as "asleep" (core, deep, REM, unspecified).
    /// Intervals are sorted by start time and merged greedily.
    ///
    /// - Parameter points: Raw sleep analysis data points.
    /// - Returns: Sorted, merged (start, end) tuples.
    static func mergedSleepIntervals(from points: [HealthDataPoint]) -> [(start: Date, end: Date)] {
        let sorted = points
            .filter(isAsleepSample)
            .map { (start: $0.startDate, end: $0.endDate) }
            .filter { $0.end > $0.start }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start {
                    return lhs.end < rhs.end
                }
                return lhs.start < rhs.start
            }

        guard let first = sorted.first else { return [] }

        var merged: [(start: Date, end: Date)] = [first]
        for interval in sorted.dropFirst() {
            let previous = merged[merged.count - 1]
            if interval.start <= previous.end {
                merged[merged.count - 1].end = max(previous.end, interval.end)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    /// Returns whether a sleep data point represents actual sleep
    /// (core, deep, REM, or unspecified asleep) versus in-bed or awake.
    ///
    /// - Parameter point: A sleep analysis data point.
    /// - Returns: `true` if the sample is an asleep category.
    static func isAsleepSample(_ point: HealthDataPoint) -> Bool {
        guard point.metricType == .sleepAnalysis else { return true }
        guard let categoryValue = point.categoryValue else { return true }

        #if canImport(HealthKit)
        switch categoryValue {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
             HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
             HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return true
        default:
            return false
        }
        #else
        // On non-Apple platforms, accept all values.
        return true
        #endif
    }

    // MARK: - Single Metric Payload

    /// Builds a payload dictionary for a single non-sleep metric data point.
    ///
    /// Handles the percentage multiplication (body fat, SpO2: fraction -> %)
    /// and integer rounding (steps, flights climbed).
    ///
    /// - Parameters:
    ///   - point: The health data point.
    ///   - formatter: An ISO 8601 date formatter.
    /// - Returns: A dictionary payload ready for JSON serialization.
    static func metricPayload(
        for point: HealthDataPoint,
        formatter: ISO8601DateFormatter
    ) -> [String: Any] {
        var displayValue = point.value
        switch point.metricType {
        case .bodyFatPercentage,
             .oxygenSaturation:
            displayValue *= 100
        default:
            break
        }

        let roundedValue: Any = switch point.metricType {
        case .steps,
             .flightsClimbed:
            Int(displayValue)
        default:
            (displayValue * 100).rounded() / 100
        }

        return [
            "id": point.id.uuidString,
            "type": point.metricType.fileStem,
            "value": roundedValue,
            "unit": point.metricType.displayUnit,
            "start_date": formatter.string(from: point.startDate),
            "end_date": formatter.string(from: point.endDate)
        ]
    }

    // MARK: - Private

    private static let sleepAggregateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
