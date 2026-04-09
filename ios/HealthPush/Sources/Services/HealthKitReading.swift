import Foundation

// MARK: - HealthKitReading

/// Abstracts HealthKit data access so the ``SyncEngine`` can be tested
/// without a real `HKHealthStore`.
///
/// ``HealthKitManager`` conforms to this protocol in production. Tests inject a
/// fake implementation that returns canned data.
protocol HealthKitReading: Sendable {
    /// Queries discrete health data for the given metrics within a date range.
    func queryData(
        for metrics: Set<HealthMetricType>,
        from start: Date,
        to end: Date
    ) async -> HealthDataQueryResult

    /// Queries daily aggregated statistics for cumulative metrics.
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

    /// Resets stored anchor data, forcing a full re-sync next time.
    func resetAnchors() async
}
