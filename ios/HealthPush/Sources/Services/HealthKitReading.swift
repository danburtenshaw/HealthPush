import Foundation

// MARK: - HealthAnchoredQueryResult

/// Result of an anchor-based incremental query for one or more metrics.
///
/// `newAnchors` should be persisted by the caller *after* the data has been
/// successfully delivered to the destination — never before, because losing the
/// data would create a gap (the next sync would skip past it).
struct HealthAnchoredQueryResult {
    /// Samples returned for the queried metrics, across all metric types.
    var dataPoints: [HealthDataPoint]

    /// Per-metric query failures. A metric appearing here will NOT have its
    /// anchor advanced in `newAnchors`, so the next sync will retry it.
    var issues: [HealthMetricQueryIssue]

    /// Updated anchor blobs per metric. Only present for metrics that succeeded.
    /// Encode using ``MetricSyncAnchor/encode(_:)``-compatible NSKeyedArchiver
    /// data so the engine can store them via SwiftData.
    var newAnchors: [HealthMetricType: Data]

    init(
        dataPoints: [HealthDataPoint] = [],
        issues: [HealthMetricQueryIssue] = [],
        newAnchors: [HealthMetricType: Data] = [:]
    ) {
        self.dataPoints = dataPoints
        self.issues = issues
        self.newAnchors = newAnchors
    }
}

// MARK: - HealthKitReading

/// Abstracts HealthKit data access so the ``SyncEngine`` can be tested
/// without a real `HKHealthStore`.
///
/// ``HealthKitManager`` conforms to this protocol in production. Tests inject a
/// fake implementation that returns canned data.
protocol HealthKitReading: Sendable {
    /// Queries discrete metrics using HKAnchoredObjectQuery.
    ///
    /// For each metric:
    /// - If `anchors[metric]` is non-nil, returns only samples added/modified
    ///   in HealthKit since that anchor (regardless of sample timestamp). This
    ///   correctly catches late-arriving Apple Watch samples because the anchor
    ///   tracks database insertion order, not sample dates.
    /// - If `anchors[metric]` is nil, returns all samples in `[fallbackStart, end]`
    ///   along with a fresh anchor that the caller should persist after success.
    ///
    /// - Parameters:
    ///   - metrics: The discrete (non-cumulative) metrics to query.
    ///   - anchors: Per-metric stored anchor blobs (NSKeyedArchiver data).
    ///   - fallbackStart: Lookback window start used only when no anchor exists.
    ///   - end: Upper bound for the fallback window (typically now).
    /// - Returns: Samples + updated anchors for metrics that succeeded.
    func queryData(
        for metrics: Set<HealthMetricType>,
        anchors: [HealthMetricType: Data],
        fallbackStart: Date,
        end: Date
    ) async -> HealthAnchoredQueryResult

    /// Queries daily aggregated statistics for cumulative metrics
    /// (steps, distance, energy). Uses a date window because aggregations are
    /// not anchor-friendly — the daily total can change retroactively when late
    /// samples arrive.
    func queryDailyStatistics(
        for metrics: Set<HealthMetricType>,
        from start: Date,
        to end: Date
    ) async -> HealthDataQueryResult

    /// Enables background delivery for the given metrics.
    func enableBackgroundDelivery(
        for metrics: Set<HealthMetricType>,
        onUpdate: @escaping @Sendable () async -> Void
    ) async

    /// Requests HealthKit authorization for the given metrics.
    func requestAuthorization(for metrics: Set<HealthMetricType>) async throws
}
