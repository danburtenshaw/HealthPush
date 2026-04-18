import Foundation
@preconcurrency import HealthKit
import os

// MARK: - HealthKitError

/// Errors that can occur during HealthKit operations.
enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationDenied
    case queryFailed(String)
    case noData
    case invalidType(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "HealthKit is not available on this device."
        case .authorizationDenied:
            "HealthKit authorization was denied. Please enable it in Settings."
        case let .queryFailed(message):
            "HealthKit query failed: \(message)"
        case .noData:
            "No health data found for the requested period."
        case let .invalidType(type):
            "Invalid health metric type: \(type)"
        }
    }
}

// MARK: - HealthDataQueryResult

struct HealthMetricQueryIssue {
    let metric: HealthMetricType
    let errorDescription: String
}

struct HealthDataQueryResult {
    var dataPoints: [HealthDataPoint]
    var issues: [HealthMetricQueryIssue]
}

// MARK: - HealthKitManager

/// Actor responsible for all HealthKit interactions.
///
/// This actor serializes access to HKHealthStore and provides async methods
/// for authorization, querying, and anchor-based incremental queries.
actor HealthKitManager: HealthKitReading {
    // MARK: Properties

    private let healthStore: HKHealthStore
    private let logger = Logger(subsystem: "app.healthpush", category: "HealthKit")
    private let signposter = OSSignposter(subsystem: "app.healthpush", category: "Performance")
    private var observerQueries: [HKObserverQuery] = []

    // MARK: Initialization

    /// Creates a new HealthKit manager.
    /// - Throws: `HealthKitError.notAvailable` if HealthKit is not supported.
    init() throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        healthStore = HKHealthStore()
    }

    // MARK: Authorization

    /// Whether HealthKit is available on this device.
    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Requests HealthKit authorization for the given metric types.
    /// - Parameter metrics: The health metrics to request read access for.
    func requestAuthorization(for metrics: Set<HealthMetricType>) async throws {
        let readTypes: [HKObjectType] = metrics.compactMap(\.hkSampleType)
        guard !readTypes.isEmpty else { return }

        let typesToRead = Set(readTypes)

        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
        logger.info("HealthKit authorization requested for \(metrics.count) types")
    }

    /// Checks the authorization status for a specific metric type.
    /// - Parameter metric: The metric to check.
    /// - Returns: The current authorization status.
    func authorizationStatus(for metric: HealthMetricType) -> HKAuthorizationStatus {
        guard let sampleType: HKObjectType = metric.hkSampleType else {
            return .notDetermined
        }
        return healthStore.authorizationStatus(for: sampleType)
    }

    // MARK: Queries

    /// Queries discrete metrics using HKAnchoredObjectQuery.
    ///
    /// When an anchor is present for a metric, only samples added/modified in
    /// HealthKit since that anchor are returned — regardless of the sample's
    /// own start/end date. This correctly captures late-arriving Apple Watch
    /// data because anchors track database insertion order, not sample
    /// timestamps.
    ///
    /// When no anchor is present (first sync after install/reset), the
    /// `fallbackStart` window is used, and a fresh anchor is returned for the
    /// caller to persist after a successful destination delivery.
    func queryData(
        for metrics: Set<HealthMetricType>,
        anchors: [HealthMetricType: Data],
        fallbackStart: Date,
        end: Date
    ) async -> HealthAnchoredQueryResult {
        let state = signposter.beginInterval("queryData")
        var allDataPoints: [HealthDataPoint] = []
        var issues: [HealthMetricQueryIssue] = []
        var newAnchors: [HealthMetricType: Data] = [:]

        for metric in metrics {
            do {
                let storedAnchor = try anchors[metric].flatMap { try MetricSyncAnchor.decode($0) }
                let result = try await queryAnchoredMetric(
                    metric,
                    previousAnchor: storedAnchor,
                    fallbackStart: fallbackStart,
                    end: end
                )
                allDataPoints.append(contentsOf: result.dataPoints)
                if let nextAnchor = result.newAnchor {
                    let encoded = try MetricSyncAnchor.encode(nextAnchor)
                    newAnchors[metric] = encoded
                }
            } catch {
                logger.warning("Failed to query \(metric.rawValue): \(error.localizedDescription)")
                issues.append(HealthMetricQueryIssue(
                    metric: metric,
                    errorDescription: error.localizedDescription
                ))
            }
        }

        signposter.endInterval("queryData", state)
        return HealthAnchoredQueryResult(
            dataPoints: allDataPoints,
            issues: issues,
            newAnchors: newAnchors
        )
    }

    /// Queries daily aggregated statistics for cumulative metrics.
    ///
    /// Uses `HKStatisticsCollectionQuery` with `.cumulativeSum` to get
    /// Apple's deduplicated totals per day. Non-cumulative metrics are skipped.
    ///
    /// - Parameters:
    ///   - metrics: Health metrics to query (non-cumulative ones are ignored).
    ///   - start: The start of the date range (aligned to start of day internally).
    ///   - end: The end of the date range.
    /// - Returns: One `HealthDataPoint` per metric per day with deduplicated totals.
    func queryDailyStatistics(
        for metrics: Set<HealthMetricType>,
        from start: Date,
        to end: Date
    ) async -> HealthDataQueryResult {
        let state = signposter.beginInterval("queryDailyStatistics")
        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: start)
        let daily = DateComponents(day: 1)

        var allDataPoints: [HealthDataPoint] = []
        var issues: [HealthMetricQueryIssue] = []

        for metric in metrics where metric.isCumulative {
            guard let quantityType = metric.hkQuantityType, let unit = metric.hkUnit else { continue }

            do {
                let points = try await queryStatisticsCollection(
                    metric: metric,
                    quantityType: quantityType,
                    unit: unit,
                    start: anchorDate,
                    end: end,
                    interval: daily,
                    anchorDate: anchorDate
                )
                allDataPoints.append(contentsOf: points)
            } catch {
                logger.warning("Failed to query statistics for \(metric.rawValue): \(error.localizedDescription)")
                issues.append(HealthMetricQueryIssue(
                    metric: metric,
                    errorDescription: error.localizedDescription
                ))
            }
        }

        signposter.endInterval("queryDailyStatistics", state)
        return HealthDataQueryResult(dataPoints: allDataPoints, issues: issues)
    }

    // MARK: Private Query Methods

    private func queryStatisticsCollection(
        metric: HealthMetricType,
        quantityType: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        interval: DateComponents,
        anchorDate: Date
    ) async throws -> [HealthDataPoint] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }

                guard let results else {
                    continuation.resume(returning: [])
                    return
                }

                let calendar = Calendar.current
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                df.locale = Locale(identifier: "en_US_POSIX")

                var dataPoints: [HealthDataPoint] = []

                results.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let sum = statistics.sumQuantity() else { return }
                    let value = sum.doubleValue(for: unit)
                    guard value > 0 else { return }

                    let dayStart = statistics.startDate
                    let dayEnd = statistics.endDate
                    let dateString = df.string(from: calendar.startOfDay(for: dayStart))
                    let aggregateID = HealthDataPoint.aggregateID(date: dateString, metric: metric)

                    dataPoints.append(HealthDataPoint(
                        id: aggregateID,
                        metricType: metric,
                        value: value,
                        unit: metric.canonicalUnit,
                        startDate: dayStart,
                        endDate: dayEnd,
                        sourceName: "HealthKit Aggregate",
                        sourceBundleIdentifier: nil,
                        aggregation: "sum"
                    ))
                }

                continuation.resume(returning: dataPoints)
            }

            self.healthStore.execute(query)
        }
    }

    /// Single-metric anchored query result, internal to the manager.
    private struct AnchoredMetricResult {
        let dataPoints: [HealthDataPoint]
        let newAnchor: HKQueryAnchor?
    }

    private func queryAnchoredMetric(
        _ metric: HealthMetricType,
        previousAnchor: HKQueryAnchor?,
        fallbackStart: Date,
        end: Date
    ) async throws -> AnchoredMetricResult {
        if metric.isCategoryType {
            try await queryAnchoredCategoryMetric(metric, previousAnchor: previousAnchor, fallbackStart: fallbackStart, end: end)
        } else {
            try await queryAnchoredQuantityMetric(metric, previousAnchor: previousAnchor, fallbackStart: fallbackStart, end: end)
        }
    }

    private func queryAnchoredQuantityMetric(
        _ metric: HealthMetricType,
        previousAnchor: HKQueryAnchor?,
        fallbackStart: Date,
        end: Date
    ) async throws -> AnchoredMetricResult {
        guard let quantityType = metric.hkQuantityType, let unit = metric.hkUnit else {
            throw HealthKitError.invalidType(metric.rawValue)
        }

        // No date predicate when an anchor exists — we want every newly inserted
        // sample regardless of its timestamp, which is how late-arriving Watch
        // backfills get caught. The fallback window only applies on first sync.
        let predicate: HKSamplePredicate<HKQuantitySample>
        if previousAnchor == nil {
            let datePredicate = HKQuery.predicateForSamples(
                withStart: fallbackStart,
                end: end,
                options: .strictStartDate
            )
            predicate = .quantitySample(type: quantityType, predicate: datePredicate)
        } else {
            predicate = .quantitySample(type: quantityType)
        }

        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [predicate],
            anchor: previousAnchor
        )

        // HKAnchoredObjectQueryDescriptor.Result isn't annotated Sendable in
        // current iOS SDKs, so awaiting it from this actor trips strict
        // concurrency under stricter toolchains. We immediately copy the
        // payload into Sendable HealthDataPoint values, so the unsafe escape
        // is bounded to this scope.
        nonisolated(unsafe) let result = try await descriptor.result(for: healthStore)

        let dataPoints = result.addedSamples.map { sample in
            HealthDataPoint(
                id: sample.uuid,
                metricType: metric,
                value: sample.quantity.doubleValue(for: unit),
                unit: metric.canonicalUnit,
                startDate: sample.startDate,
                endDate: sample.endDate,
                sourceName: sample.sourceRevision.source.name,
                sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                categoryValue: nil,
                aggregation: "raw"
            )
        }

        return AnchoredMetricResult(dataPoints: dataPoints, newAnchor: result.newAnchor)
    }

    private func queryAnchoredCategoryMetric(
        _ metric: HealthMetricType,
        previousAnchor: HKQueryAnchor?,
        fallbackStart: Date,
        end: Date
    ) async throws -> AnchoredMetricResult {
        guard let categoryType = metric.hkCategoryType else {
            throw HealthKitError.invalidType(metric.rawValue)
        }

        let predicate: HKSamplePredicate<HKCategorySample>
        if previousAnchor == nil {
            let datePredicate = HKQuery.predicateForSamples(
                withStart: fallbackStart,
                end: end,
                options: .strictStartDate
            )
            predicate = .categorySample(type: categoryType, predicate: datePredicate)
        } else {
            predicate = .categorySample(type: categoryType)
        }

        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [predicate],
            anchor: previousAnchor
        )

        // See queryAnchoredQuantityMetric for the rationale behind nonisolated(unsafe).
        nonisolated(unsafe) let result = try await descriptor.result(for: healthStore)

        let dataPoints = result.addedSamples.map { sample in
            let durationSeconds = sample.endDate.timeIntervalSince(sample.startDate)
            return HealthDataPoint(
                id: sample.uuid,
                metricType: metric,
                value: durationSeconds,
                unit: metric.canonicalUnit,
                startDate: sample.startDate,
                endDate: sample.endDate,
                sourceName: sample.sourceRevision.source.name,
                sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                categoryValue: sample.value,
                aggregation: "raw"
            )
        }

        return AnchoredMetricResult(dataPoints: dataPoints, newAnchor: result.newAnchor)
    }

    // MARK: Background Delivery

    /// Enables HealthKit background delivery for the given metric types.
    ///
    /// Registers an `HKObserverQuery` per metric type and calls
    /// `enableBackgroundDelivery(for:frequency:.immediate)` so iOS wakes the app
    /// when new health data arrives (e.g., from Apple Watch).
    ///
    /// - Parameters:
    ///   - metrics: The health metrics to observe.
    ///   - onUpdate: A callback invoked when new data is available. All observers
    ///     share a single callback to allow debouncing at the call site.
    func enableBackgroundDelivery(
        for metrics: Set<HealthMetricType>,
        onUpdate: @escaping @Sendable () async -> Void
    ) async {
        stopObserverQueries()

        for metric in metrics {
            guard let sampleType = metric.hkSampleType else { continue }

            do {
                try await healthStore.enableBackgroundDelivery(
                    for: sampleType,
                    frequency: .immediate
                )
            } catch {
                logger.warning("Failed to enable background delivery for \(metric.rawValue): \(error.localizedDescription)")
                continue
            }

            let query = HKObserverQuery(
                sampleType: sampleType,
                predicate: nil
            ) { _, completionHandler, error in
                if let error {
                    Logger(subsystem: "app.healthpush", category: "HealthKit")
                        .warning("Observer query error for \(metric.rawValue): \(error.localizedDescription)")
                    completionHandler()
                    return
                }
                // Call completionHandler immediately per Apple docs — deferring it
                // causes HealthKit to throttle/stop background delivery.
                // The sync work runs asynchronously after.
                completionHandler()
                Task {
                    await onUpdate()
                }
            }

            healthStore.execute(query)
            observerQueries.append(query)
        }

        let observerCount = observerQueries.count
        logger.info("Background delivery enabled for \(metrics.count) metric types with \(observerCount) observer queries")
    }

    /// Stops all active observer queries.
    func stopObserverQueries() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
    }
}
