import Foundation
import HealthKit
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

    /// Queries health data for the given metrics within a date range.
    /// - Parameters:
    ///   - metrics: The health metrics to query.
    ///   - start: The start of the date range.
    ///   - end: The end of the date range.
    /// - Returns: An array of health data points.
    func queryData(
        for metrics: Set<HealthMetricType>,
        from start: Date,
        to end: Date
    ) async -> HealthDataQueryResult {
        let state = signposter.beginInterval("queryData")
        var allDataPoints: [HealthDataPoint] = []
        var issues: [HealthMetricQueryIssue] = []

        for metric in metrics {
            do {
                let points = try await querySingleMetric(metric, from: start, to: end)
                allDataPoints.append(contentsOf: points)
            } catch {
                logger.warning("Failed to query \(metric.rawValue): \(error.localizedDescription)")
                issues.append(HealthMetricQueryIssue(
                    metric: metric,
                    errorDescription: error.localizedDescription
                ))
            }
        }

        signposter.endInterval("queryData", state)
        return HealthDataQueryResult(dataPoints: allDataPoints, issues: issues)
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

    private func querySingleMetric(
        _ metric: HealthMetricType,
        from start: Date,
        to end: Date
    ) async throws -> [HealthDataPoint] {
        if metric.isCategoryType {
            try await queryCategoryMetric(metric, from: start, to: end)
        } else {
            try await queryQuantityMetric(metric, from: start, to: end)
        }
    }

    private func queryQuantityMetric(
        _ metric: HealthMetricType,
        from start: Date,
        to end: Date
    ) async throws -> [HealthDataPoint] {
        guard let quantityType = metric.hkQuantityType, let unit = metric.hkUnit else {
            throw HealthKitError.invalidType(metric.rawValue)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: quantityType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: HKObjectQueryNoLimit
        )

        let samples = try await descriptor.result(for: healthStore)

        return samples.map { sample in
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
    }

    private func queryCategoryMetric(
        _ metric: HealthMetricType,
        from start: Date,
        to end: Date
    ) async throws -> [HealthDataPoint] {
        guard let categoryType = metric.hkCategoryType else {
            throw HealthKitError.invalidType(metric.rawValue)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: categoryType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: HKObjectQueryNoLimit
        )

        let samples = try await descriptor.result(for: healthStore)

        return samples.map { sample in
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

    /// Resets stored sync state (clears anchor data from UserDefaults).
    func resetAnchors() {
        UserDefaults.standard.removeObject(forKey: "healthkit_anchors")
        logger.info("HealthKit sync state reset")
    }
}
