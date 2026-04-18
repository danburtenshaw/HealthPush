import Foundation
import HealthKit
import SwiftData

// MARK: - MetricSyncAnchor

/// Persistent `HKQueryAnchor` for a single (destination, metric) pair.
///
/// HealthKit anchors track changes by *database insertion order*, not sample
/// timestamp, so saving and re-using the anchor lets the next sync pick up
/// every new sample written to HealthKit since last time — including
/// late-arriving Apple Watch backfills with old sample dates. This replaces
/// the previous "re-query the last 3 days every time" lookback with a true
/// incremental delta.
///
/// Anchors are stored per-destination so each destination can advance
/// independently: an S3 sync that succeeded last hour shouldn't re-send data
/// just because a Home Assistant sync failed.
@Model
final class MetricSyncAnchor {
    /// Stable record ID.
    var id: UUID

    /// The destination this anchor belongs to (matches `DestinationConfig.id`).
    var destinationID: UUID

    /// The HealthKit metric this anchor tracks (e.g. `"heartRate"`).
    var metricRawValue: String

    /// Archived `HKQueryAnchor` blob produced by `NSKeyedArchiver`.
    var anchorData: Data

    /// When this anchor was last updated. Diagnostic only.
    var lastUpdated: Date

    init(destinationID: UUID, metric: HealthMetricType, anchorData: Data, lastUpdated: Date = .now) {
        id = UUID()
        self.destinationID = destinationID
        metricRawValue = metric.rawValue
        self.anchorData = anchorData
        self.lastUpdated = lastUpdated
    }

    /// The strongly-typed metric this anchor tracks.
    var metric: HealthMetricType? {
        HealthMetricType(rawValue: metricRawValue)
    }
}

// MARK: - HKQueryAnchor archiving

extension MetricSyncAnchor {
    /// Encodes an `HKQueryAnchor` for SwiftData storage.
    static func encode(_ anchor: HKQueryAnchor) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    /// Decodes a previously archived anchor blob.
    static func decode(_ data: Data) throws -> HKQueryAnchor? {
        try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}
