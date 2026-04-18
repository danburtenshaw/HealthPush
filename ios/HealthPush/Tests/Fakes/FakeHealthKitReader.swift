import Foundation
@testable import HealthPush

/// A test fake for ``HealthKitReading`` that returns canned results without
/// touching a real `HKHealthStore`.
final class FakeHealthKitReader: HealthKitReading, @unchecked Sendable {
    // MARK: Configurable Results

    /// Result returned by ``queryData(for:anchors:fallbackStart:end:)``.
    /// Defaults to an empty result with no new anchors.
    var queryDataResult = HealthAnchoredQueryResult(dataPoints: [], issues: [], newAnchors: [:])

    /// Result returned by ``queryDailyStatistics(for:from:to:)``.
    var queryStatsResult = HealthDataQueryResult(dataPoints: [], issues: [])

    /// If non-nil, ``requestAuthorization(for:)`` throws this error.
    var authorizationError: Error?

    // MARK: Call Tracking

    /// Number of times ``queryData`` was called.
    var queryDataCallCount = 0

    /// Number of times ``queryDailyStatistics`` was called.
    var queryStatsCallCount = 0

    /// Number of times ``requestAuthorization`` was called.
    var requestAuthCallCount = 0

    /// Anchors passed in on the most recent ``queryData`` call.
    var lastQueriedAnchors: [HealthMetricType: Data] = [:]

    /// Fallback-start passed in on the most recent ``queryData`` call.
    var lastFallbackStart: Date?

    // MARK: HealthKitReading

    func queryData(
        for metrics: Set<HealthMetricType>,
        anchors: [HealthMetricType: Data],
        fallbackStart: Date,
        end: Date
    ) async -> HealthAnchoredQueryResult {
        queryDataCallCount += 1
        lastQueriedAnchors = anchors
        lastFallbackStart = fallbackStart
        return queryDataResult
    }

    func queryDailyStatistics(
        for metrics: Set<HealthMetricType>,
        from start: Date,
        to end: Date
    ) async -> HealthDataQueryResult {
        queryStatsCallCount += 1
        return queryStatsResult
    }

    func enableBackgroundDelivery(
        for metrics: Set<HealthMetricType>,
        onUpdate: @escaping @Sendable () async -> Void
    ) async {
        // No-op in tests
    }

    func requestAuthorization(for metrics: Set<HealthMetricType>) async throws {
        requestAuthCallCount += 1
        if let error = authorizationError { throw error }
    }
}
