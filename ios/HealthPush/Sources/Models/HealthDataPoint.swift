import CryptoKit
import Foundation

// MARK: - HealthDataPoint

/// A single health data measurement that can be synced to a destination.
///
/// This is the canonical interchange format between HealthKit queries
/// and sync destinations. It is fully value-typed and `Sendable`.
struct HealthDataPoint: Identifiable, Codable, Sendable, Equatable {

    /// Stable identifier derived from the HealthKit sample UUID.
    let id: UUID

    /// The metric type this data point represents.
    let metricType: HealthMetricType

    /// The numeric value of the measurement.
    let value: Double

    /// The unit string (e.g. "bpm", "steps", "kg").
    let unit: String

    /// When the sample was recorded (start date of the HealthKit sample).
    let timestamp: Date

    /// When the sample period ended (end date of the HealthKit sample).
    let endTimestamp: Date

    /// The source device or app that produced the sample.
    let sourceName: String

    /// Optional source bundle identifier.
    let sourceBundleIdentifier: String?

    /// Optional raw HealthKit category value for category-based samples.
    let categoryValue: Int?

    /// Creates a new health data point.
    /// - Parameters:
    ///   - id: Unique identifier, typically from the HealthKit sample UUID.
    ///   - metricType: The type of health metric.
    ///   - value: The numeric measurement value.
    ///   - unit: The unit of measurement.
    ///   - timestamp: The start time of the measurement.
    ///   - endTimestamp: The end time of the measurement.
    ///   - sourceName: The name of the source device or app.
    ///   - sourceBundleIdentifier: Optional bundle identifier of the source app.
    init(
        id: UUID = UUID(),
        metricType: HealthMetricType,
        value: Double,
        unit: String,
        timestamp: Date,
        endTimestamp: Date,
        sourceName: String,
        sourceBundleIdentifier: String? = nil,
        categoryValue: Int? = nil
    ) {
        self.id = id
        self.metricType = metricType
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.categoryValue = categoryValue
    }

    // MARK: - Aggregate ID

    /// Creates a deterministic UUID for a daily aggregate data point.
    ///
    /// S3 deduplicates by UUID. For cumulative aggregates, the UUID must be
    /// stable so that re-syncing the same date+metric replaces the old value
    /// instead of accumulating duplicate rows.
    ///
    /// - Parameters:
    ///   - dateString: The date in "yyyy-MM-dd" format.
    ///   - metric: The health metric type.
    /// - Returns: A stable UUID that is always the same for the given inputs.
    static func aggregateID(date dateString: String, metric: HealthMetricType) -> UUID {
        let input = "\(dateString):\(metric.rawValue)"
        let digest = SHA256.hash(data: Data(input.utf8))

        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // UUID version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant

        return UUID(uuid: (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
