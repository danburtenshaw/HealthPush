import Foundation

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

// MARK: - HealthDataPoint

/// A single health data measurement that can be synced to a destination.
///
/// This is the canonical interchange format between HealthKit queries
/// and sync destinations. It is fully value-typed and `Sendable`.
///
/// ## v1 Schema Contract
///
/// The JSON representation uses nested `metric` and `source` objects:
/// ```json
/// {
///   "schemaVersion": "1.0",
///   "uuid": "...",
///   "metric": { "key": "heart_rate", "hkIdentifier": "HKQuantityTypeIdentifierHeartRate", "kind": "quantity" },
///   "value": 72.0,
///   "unit": "count/min",
///   "startDate": "2026-04-09T12:00:00.000Z",
///   "endDate": "2026-04-09T12:00:00.000Z",
///   "tzOffset": "+01:00",
///   "source": { "name": "Apple Watch", "bundleId": "com.apple.health" },
///   "aggregation": "raw",
///   "categoryValue": null
/// }
/// ```
struct HealthDataPoint: Identifiable, Equatable {
    /// Stable identifier derived from the HealthKit sample UUID.
    let id: UUID

    /// The metric type this data point represents.
    let metricType: HealthMetricType

    /// The numeric value of the measurement.
    let value: Double

    /// The unit string (canonical unit, e.g. "count/min", "kg", "m").
    let unit: String

    /// When the sample was recorded (start date of the HealthKit sample).
    let startDate: Date

    /// When the sample period ended (end date of the HealthKit sample).
    let endDate: Date

    /// The source device or app that produced the sample.
    let sourceName: String

    /// Optional source bundle identifier.
    let sourceBundleIdentifier: String?

    /// Optional raw HealthKit category value for category-based samples.
    let categoryValue: Int?

    /// Schema version for the v1 data contract.
    let schemaVersion: String

    /// UTC offset of the local timezone at sample creation time, formatted as `+HH:MM` or `-HH:MM`.
    let tzOffset: String

    /// Aggregation type: `"raw"` for discrete samples, `"sum"` for cumulative aggregates.
    let aggregation: String

    /// Whether this record is a tombstone marking a deleted sample.
    let deleted: Bool

    /// When the record was marked as deleted, if applicable.
    let deletedAt: Date?

    /// Creates a new health data point.
    /// - Parameters:
    ///   - id: Unique identifier, typically from the HealthKit sample UUID.
    ///   - metricType: The type of health metric.
    ///   - value: The numeric measurement value.
    ///   - unit: The unit of measurement.
    ///   - startDate: The start time of the measurement.
    ///   - endDate: The end time of the measurement.
    ///   - sourceName: The name of the source device or app.
    ///   - sourceBundleIdentifier: Optional bundle identifier of the source app.
    ///   - categoryValue: Optional HealthKit category value.
    ///   - aggregation: `"raw"` for discrete samples, `"sum"` for cumulative aggregates.
    ///   - tzOffset: UTC offset string; defaults to current timezone.
    ///   - deleted: Whether this is a tombstone record.
    ///   - deletedAt: When the record was deleted.
    init(
        id: UUID = UUID(),
        metricType: HealthMetricType,
        value: Double,
        unit: String,
        startDate: Date,
        endDate: Date,
        sourceName: String,
        sourceBundleIdentifier: String? = nil,
        categoryValue: Int? = nil,
        aggregation: String = "raw",
        tzOffset: String? = nil,
        deleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.metricType = metricType
        self.value = value
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.categoryValue = categoryValue
        self.schemaVersion = "1.0"
        self.tzOffset = tzOffset ?? Self.currentTZOffset()
        self.aggregation = aggregation
        self.deleted = deleted
        self.deletedAt = deletedAt
    }

    // MARK: - Source Metadata Stripping

    /// Returns a copy of this data point with source metadata removed.
    ///
    /// When the user has opted out of including source information, this method
    /// produces a point with empty `sourceName` and nil `sourceBundleIdentifier`,
    /// preventing the export from revealing which app or device recorded the measurement.
    func strippingSourceMetadata() -> HealthDataPoint {
        HealthDataPoint(
            id: id,
            metricType: metricType,
            value: value,
            unit: unit,
            startDate: startDate,
            endDate: endDate,
            sourceName: "",
            sourceBundleIdentifier: nil,
            categoryValue: categoryValue,
            aggregation: aggregation,
            tzOffset: tzOffset,
            deleted: deleted,
            deletedAt: deletedAt
        )
    }

    // MARK: - Timezone Offset

    /// Computes the current local timezone offset as a `+HH:MM` or `-HH:MM` string.
    static func currentTZOffset() -> String {
        let seconds = TimeZone.current.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let h = abs(seconds) / 3600
        let m = (abs(seconds) % 3600) / 60
        return String(format: "%@%02d:%02d", sign, h, m)
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
    ///   - aggregation: The aggregation type (default `"sum"`).
    /// - Returns: A stable UUID that is always the same for the given inputs.
    static func aggregateID(date dateString: String, metric: HealthMetricType, aggregation: String = "sum") -> UUID {
        let input = "\(dateString):\(metric.rawValue):\(aggregation)"
        let digest = SHA256.hash(data: Data(input.utf8))

        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // UUID version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

// MARK: - Codable

extension HealthDataPoint: Codable {
    private enum RootKeys: String, CodingKey {
        case schemaVersion
        case uuid
        case metric
        case value
        case unit
        case startDate
        case endDate
        case tzOffset
        case source
        case aggregation
        case categoryValue
        case deleted
        case deletedAt
    }

    private enum MetricKeys: String, CodingKey {
        case key
        case hkIdentifier
        case kind
    }

    private enum SourceKeys: String, CodingKey {
        case name
        case bundleId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RootKeys.self)

        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id.uuidString, forKey: .uuid)

        var metricContainer = container.nestedContainer(keyedBy: MetricKeys.self, forKey: .metric)
        try metricContainer.encode(metricType.fileStem, forKey: .key)
        try metricContainer.encode(metricType.hkIdentifierString, forKey: .hkIdentifier)
        try metricContainer.encode(metricType.metricKind, forKey: .kind)

        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)

        let isoFormatter = HealthDataExporter.isoFormatter
        try container.encode(isoFormatter.string(from: startDate), forKey: .startDate)
        try container.encode(isoFormatter.string(from: endDate), forKey: .endDate)
        try container.encode(tzOffset, forKey: .tzOffset)

        var sourceContainer = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
        try sourceContainer.encode(sourceName, forKey: .name)
        try sourceContainer.encode(sourceBundleIdentifier ?? "", forKey: .bundleId)

        try container.encode(aggregation, forKey: .aggregation)
        try container.encode(categoryValue, forKey: .categoryValue)
        try container.encode(deleted, forKey: .deleted)
        try container.encodeIfPresent(deletedAt.map { HealthDataExporter.isoFormatter.string(from: $0) }, forKey: .deletedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RootKeys.self)

        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "1.0"

        let uuidString = try container.decode(String.self, forKey: .uuid)
        guard let uuid = UUID(uuidString: uuidString) else {
            throw DecodingError.dataCorruptedError(forKey: .uuid, in: container, debugDescription: "Invalid UUID: \(uuidString)")
        }
        id = uuid

        let metricContainer = try container.nestedContainer(keyedBy: MetricKeys.self, forKey: .metric)
        let metricKey = try metricContainer.decode(String.self, forKey: .key)
        guard let metric = HealthMetricType.allCases.first(where: { $0.fileStem == metricKey }) else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: metricContainer, debugDescription: "Unknown metric key: \(metricKey)")
        }
        metricType = metric

        value = try container.decode(Double.self, forKey: .value)
        unit = try container.decode(String.self, forKey: .unit)

        let isoFormatter = HealthDataExporter.isoFormatter
        let startDateString = try container.decode(String.self, forKey: .startDate)
        guard let parsedStartDate = isoFormatter.date(from: startDateString) else {
            throw DecodingError.dataCorruptedError(forKey: .startDate, in: container, debugDescription: "Cannot decode date: \(startDateString)")
        }
        startDate = parsedStartDate

        let endDateString = try container.decode(String.self, forKey: .endDate)
        guard let parsedEndDate = isoFormatter.date(from: endDateString) else {
            throw DecodingError.dataCorruptedError(forKey: .endDate, in: container, debugDescription: "Cannot decode date: \(endDateString)")
        }
        endDate = parsedEndDate

        tzOffset = try container.decodeIfPresent(String.self, forKey: .tzOffset) ?? "+00:00"

        let sourceContainer = try container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
        sourceName = try sourceContainer.decode(String.self, forKey: .name)
        let bundleId = try sourceContainer.decodeIfPresent(String.self, forKey: .bundleId)
        sourceBundleIdentifier = (bundleId?.isEmpty ?? true) ? nil : bundleId

        aggregation = try container.decodeIfPresent(String.self, forKey: .aggregation) ?? "raw"
        categoryValue = try container.decodeIfPresent(Int.self, forKey: .categoryValue)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        if let deletedAtString = try container.decodeIfPresent(String.self, forKey: .deletedAt) {
            deletedAt = isoFormatter.date(from: deletedAtString)
        } else {
            deletedAt = nil
        }
    }
}
