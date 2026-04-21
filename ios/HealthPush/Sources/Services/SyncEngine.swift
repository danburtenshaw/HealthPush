import Foundation
import Observation
import os
import SwiftData

// MARK: - SyncError

/// Errors that can occur during the sync process.
enum SyncError: LocalizedError {
    case noDestinations
    case healthKitUnavailable
    case allDestinationsFailed([String])

    var errorDescription: String? {
        switch self {
        case .noDestinations:
            "No sync destinations are configured and enabled."
        case .healthKitUnavailable:
            "HealthKit is not available."
        case let .allDestinationsFailed(names):
            "All destinations failed: \(names.joined(separator: ", "))"
        }
    }
}

// MARK: - SyncDestinationError

/// A sendable record of a destination sync failure.
struct SyncDestinationError {
    let destinationName: String
    let errorDescription: String
}

// MARK: - SyncResult

/// The result of a sync operation.
struct SyncResult {
    /// Number of new or updated data points actually written to destinations.
    let dataPointCount: Int

    /// Total data points returned by HealthKit before deduplication.
    /// When this is non-zero but `dataPointCount` is zero, dedup filtered everything
    /// and the sync is working correctly -- no "no data" warning should be shown.
    let processedDataPointCount: Int

    let successfulDestinations: Int
    let failedDestinations: Int

    /// Destinations that were deferred (locked device, offline, ran out of time).
    /// Distinct from `failedDestinations` because deferred runs aren't real failures —
    /// the next sync will pick up the work without user intervention.
    let deferredDestinations: Int

    let duration: TimeInterval
    let errors: [SyncDestinationError]

    init(
        dataPointCount: Int,
        processedDataPointCount: Int,
        successfulDestinations: Int,
        failedDestinations: Int,
        deferredDestinations: Int = 0,
        duration: TimeInterval,
        errors: [SyncDestinationError]
    ) {
        self.dataPointCount = dataPointCount
        self.processedDataPointCount = processedDataPointCount
        self.successfulDestinations = successfulDestinations
        self.failedDestinations = failedDestinations
        self.deferredDestinations = deferredDestinations
        self.duration = duration
        self.errors = errors
    }
}

// MARK: - SyncEngine

/// Orchestrates the end-to-end sync flow: query HealthKit, push to destinations, record history.
///
/// The sync engine is the central coordinator that ties together the HealthKit manager,
/// destination manager, and SwiftData persistence.
@MainActor
@Observable
final class SyncEngine {
    // MARK: Properties

    private let logger = Logger(subsystem: "app.healthpush", category: "SyncEngine")
    private let signposter = OSSignposter(subsystem: "app.healthpush", category: "Performance")
    private var healthKitReader: (any HealthKitReading)?
    private let networkService: NetworkService
    private let networkMonitor: any NetworkPathMonitoring

    /// Factory closure that creates a ``SyncDestination`` from a config.
    /// Defaults to ``DestinationManager/makeDestination(for:networkService:)``.
    private let destinationFactory: @MainActor (DestinationConfig, NetworkService) throws -> any SyncDestination

    /// Default fallback window when no anchor exists yet (first sync after install
    /// or after a manual reset). HealthKit data older than this on first run will
    /// not be backfilled — subsequent syncs use anchors and pick up everything new.
    private static let initialFallbackLookbackDays = 7

    /// Daily-statistics window for cumulative metrics. Re-queries the last few
    /// days every sync so late-arriving samples get folded into the right
    /// daily total. Safe because output is small (one point per day per metric)
    /// and uploads are idempotent at the destination layer.
    private static let cumulativeRollingLookbackDays = 3

    // MARK: Initialization

    /// Creates a sync engine that auto-discovers HealthKit.
    ///
    /// Attempts to create a ``HealthKitManager``. If HealthKit is unavailable on the
    /// device, the reader is set to `nil` and syncs will report a graceful error.
    init() {
        networkService = NetworkService()
        networkMonitor = NetworkPathMonitor.shared
        destinationFactory = DestinationManager.makeDestination
        do {
            healthKitReader = try HealthKitManager()
        } catch {
            logger.warning("HealthKit not available: \(error.localizedDescription)")
            healthKitReader = nil
        }
    }

    /// Creates a sync engine with injected dependencies (for testing).
    init(
        healthKitReader: (any HealthKitReading)?,
        networkService: NetworkService = NetworkService(),
        networkMonitor: any NetworkPathMonitoring = AlwaysReachableNetworkMonitor(),
        destinationFactory: @MainActor @escaping (DestinationConfig, NetworkService) throws -> any SyncDestination = DestinationManager
            .makeDestination
    ) {
        self.networkService = networkService
        self.networkMonitor = networkMonitor
        self.healthKitReader = healthKitReader
        self.destinationFactory = destinationFactory
    }

    // MARK: Sync Operations

    typealias ProgressHandler = @MainActor (String, Double) -> Void

    /// Performs a full sync for all enabled destinations.
    /// - Parameters:
    ///   - modelContext: The SwiftData model context for persistence.
    ///   - isAutomatic: Whether this sync was triggered automatically (BGTask or
    ///     HKObserverQuery) rather than by an explicit user action. Automatic
    ///     syncs respect each destination's frequency gate; manual "Sync Now"
    ///     always syncs everything.
    ///   - isBackground: Whether the app was actually in the background when the
    ///     sync started. Used only for tagging the `SyncRecord` so logs
    ///     distinguish real iOS-wake syncs from observer syncs that happened
    ///     while the app was open.
    ///   - deadline: Optional cutoff time. When set, the engine checks remaining
    ///     time between destinations and defers any unstarted work, marking it
    ///     `.deferred(.outOfTime, ...)` instead of attempting it under a doomed budget.
    ///   - onProgress: Per-destination progress callback (name, fractionComplete).
    func performSync(
        modelContext: ModelContext,
        isAutomatic: Bool = false,
        isBackground: Bool = false,
        deadline: Date? = nil,
        onProgress: ProgressHandler? = nil
    ) async -> SyncResult {
        let syncState = signposter.beginInterval("performSync")
        let startTime = Date()
        logger.info("Starting sync (automatic: \(isAutomatic), background: \(isBackground))")

        // Fetch enabled destination configs
        let descriptor = FetchDescriptor<DestinationConfig>(
            predicate: #Predicate<DestinationConfig> { config in
                config.isEnabled
            }
        )

        guard let destinations = try? modelContext.fetch(descriptor),
              !destinations.isEmpty
        else {
            logger.warning("No enabled destinations found")
            signposter.endInterval("performSync", syncState)
            return SyncResult(
                dataPointCount: 0,
                processedDataPointCount: 0,
                successfulDestinations: 0,
                failedDestinations: 0,
                deferredDestinations: 0,
                duration: Date().timeIntervalSince(startTime),
                errors: []
            )
        }

        guard let healthKitReader else {
            logger.error("HealthKit not available")
            signposter.endInterval("performSync", syncState)
            return SyncResult(
                dataPointCount: 0,
                processedDataPointCount: 0,
                successfulDestinations: 0,
                failedDestinations: 0,
                deferredDestinations: 0,
                duration: Date().timeIntervalSince(startTime),
                errors: [SyncDestinationError(
                    destinationName: "HealthKit",
                    errorDescription: SyncError.healthKitUnavailable.localizedDescription
                )]
            )
        }

        // Reachability gate — if offline, defer the whole run rather than
        // letting each destination fail with a network error.
        guard networkMonitor.isReachable else {
            logger.info("Sync deferred — network unreachable")
            return makeDeferredResult(
                for: destinations,
                modelContext: modelContext,
                isAutomatic: isAutomatic,
                isBackground: isBackground,
                reason: .offline,
                message: "No network connection — will retry when online.",
                startTime: startTime
            )
        }

        // Sync each destination independently with its own query window
        var successCount = 0
        var failCount = 0
        var deferredCount = 0
        var totalDataPoints = 0
        var totalProcessedPoints = 0
        var errors: [SyncDestinationError] = []

        for config in destinations {
            // Skip destinations with no enabled metrics — nothing to sync.
            if config.enabledMetrics.isEmpty {
                logger.info("Skipping \(config.name) — no health metrics enabled")
                continue
            }

            // Automatic syncs skip destinations that were synced recently enough
            // per their own frequency. Manual "Sync Now" always syncs everything.
            if isAutomatic,
               !config.needsFullSync,
               let lastSynced = config.lastSyncedAt,
               Date.now.timeIntervalSince(lastSynced) < config.syncFrequency.timeInterval * 0.9
            {
                logger.info("Skipping \(config.name) — last synced \(lastSynced), interval not yet elapsed")
                continue
            }

            // Time-budget gate — bail before starting a new destination if we're
            // already past the deadline. Mark remaining work as deferred-out-of-time
            // so the user sees an informational entry, not an error.
            if let deadline, Date.now >= deadline {
                logger.info("Deferring \(config.name) — out of background time")
                let record = makeRecord(for: config, startTime: startTime, isBackground: isBackground, modelContext: modelContext)
                let failure = SyncFailure.deferred(
                    reason: .outOfTime,
                    message: "Skipped — ran out of background time. Will retry next sync."
                )
                record.status = .deferred
                record.applyFailure(failure)
                record.duration = Date().timeIntervalSince(startTime)
                deferredCount += 1
                continue
            }

            let destState = signposter.beginInterval("syncDestination", id: signposter.makeSignpostID(), "\(config.name)")

            // Create the destination via the injected factory.
            let destination: any SyncDestination
            do {
                destination = try destinationFactory(config, networkService)
            } catch {
                failCount += 1
                errors.append(SyncDestinationError(
                    destinationName: config.name,
                    errorDescription: error.localizedDescription
                ))
                logger.error("Failed to create destination \(config.name): \(error.localizedDescription)")
                signposter.endInterval("syncDestination", destState)
                continue
            }

            let queryOutcome = await queryHealthData(
                for: config,
                destination: destination,
                healthKitReader: healthKitReader,
                modelContext: modelContext
            )

            // Strip source metadata (app name, bundle ID) when the user has opted out.
            let dataPoints = config.includeSourceMetadata
                ? queryOutcome.dataPoints
                : queryOutcome.dataPoints.map { $0.strippingSourceMetadata() }

            logger.info("Queried \(dataPoints.count) data points for \(config.name)")

            let result = await syncDestination(
                inputs: DestinationSyncInputs(
                    config: config,
                    destination: destination,
                    dataPoints: dataPoints,
                    queryIssues: queryOutcome.issues,
                    pendingAnchors: queryOutcome.newAnchors,
                    startTime: startTime,
                    isBackground: isBackground
                ),
                modelContext: modelContext,
                onProgress: onProgress
            )
            totalDataPoints += result.dataPointCount
            totalProcessedPoints += result.processedDataPointCount
            successCount += result.successCount
            failCount += result.failCount
            deferredCount += result.deferredCount
            errors.append(contentsOf: result.errors)

            signposter.endInterval("syncDestination", destState)
        }

        // Save sync records and updated destination configs
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save sync records: \(error.localizedDescription)")
        }

        // Prune sync records older than 30 days to limit store growth
        pruneOldSyncRecords(modelContext: modelContext)

        let duration = Date().timeIntervalSince(startTime)
        logger
            .info(
                "Sync completed in \(String(format: "%.1f", duration))s: \(successCount) succeeded, \(failCount) failed, \(deferredCount) deferred"
            )

        signposter.endInterval("performSync", syncState)
        return SyncResult(
            dataPointCount: totalDataPoints,
            processedDataPointCount: totalProcessedPoints,
            successfulDestinations: successCount,
            failedDestinations: failCount,
            deferredDestinations: deferredCount,
            duration: duration,
            errors: errors
        )
    }

    /// Enables HealthKit background delivery for the given metrics.
    func enableBackgroundDelivery(
        for metrics: Set<HealthMetricType>,
        onUpdate: @escaping @Sendable () async -> Void
    ) async {
        await healthKitReader?.enableBackgroundDelivery(for: metrics, onUpdate: onUpdate)
    }

    /// Requests HealthKit authorization for the given metrics.
    func requestHealthKitAuthorization(for metrics: Set<HealthMetricType>) async throws {
        guard let healthKitReader else {
            throw SyncError.healthKitUnavailable
        }
        try await healthKitReader.requestAuthorization(for: metrics)
    }

    /// Resets all stored sync anchors so the next sync re-fetches a wider history.
    /// Also flips every destination's `needsFullSync` back to true.
    func resetAnchors(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: MetricSyncAnchor.self)
            let descriptor = FetchDescriptor<DestinationConfig>()
            let configs = try modelContext.fetch(descriptor)
            for config in configs {
                config.needsFullSync = true
                config.lastSyncedAt = nil
            }
            try modelContext.save()
            logger.info("Reset all sync anchors and marked destinations for full re-sync")
        } catch {
            logger.error("Failed to reset anchors: \(error.localizedDescription)")
        }
    }

    // MARK: Single-Destination Sync

    /// Result of syncing a single destination, used to aggregate into the overall SyncResult.
    private struct DestinationSyncResult {
        var dataPointCount = 0
        var processedDataPointCount = 0
        var successCount = 0
        var failCount = 0
        var deferredCount = 0
        var errors: [SyncDestinationError] = []
    }

    /// Inputs for a single destination's sync. Bundling these keeps
    /// `syncDestination` under SwiftLint's parameter-count budget.
    private struct DestinationSyncInputs {
        let config: DestinationConfig
        let destination: any SyncDestination
        let dataPoints: [HealthDataPoint]
        let queryIssues: [HealthMetricQueryIssue]
        let pendingAnchors: [HealthMetricType: Data]
        let startTime: Date
        let isBackground: Bool
    }

    /// Pushes data to a single destination, records the outcome, and returns aggregate counts.
    private func syncDestination(
        inputs: DestinationSyncInputs,
        modelContext: ModelContext,
        onProgress: ProgressHandler?
    ) async -> DestinationSyncResult {
        let config = inputs.config
        let destination = inputs.destination
        let dataPoints = inputs.dataPoints
        let queryIssues = inputs.queryIssues
        let pendingAnchors = inputs.pendingAnchors
        let startTime = inputs.startTime
        let isBackground = inputs.isBackground

        var result = DestinationSyncResult()

        let record = SyncRecord(
            destinationName: config.name,
            destinationID: config.id,
            timestamp: startTime,
            status: .inProgress,
            isBackgroundSync: isBackground
        )
        modelContext.insert(record)

        do {
            let destName = config.name
            let progressCallback: @Sendable (Int, Int) -> Void = { completed, total in
                Task { @MainActor in
                    onProgress?(destName, total > 0 ? Double(completed) / Double(total) : 1.0)
                }
            }

            let stats = try await destination.sync(data: dataPoints, onProgress: progressCallback)

            result.dataPointCount = stats.newCount
            result.processedDataPointCount = stats.processedCount
            record.dataPointCount = stats.newCount
            record.duration = Date().timeIntervalSince(startTime)

            // Update last sync time and clear full-sync flag on any successful delivery.
            // Even partial success (some metric queries failed) counts — we delivered data.
            config.lastSyncedAt = .now
            if config.needsFullSync {
                config.needsFullSync = false
            }

            // Persist the new anchors only after a successful destination delivery.
            // If we'd persisted them earlier and the destination call failed, the next
            // sync would skip past the un-delivered samples and create a permanent gap.
            persistAnchors(pendingAnchors, for: config, modelContext: modelContext)

            if queryIssues.isEmpty {
                record.status = .success
                result.successCount = 1
                logger.info("Synced \(dataPoints.count) points to \(config.name)")
            } else {
                let queryMessage = queryIssues
                    .sorted { $0.metric.rawValue < $1.metric.rawValue }
                    .map { "\($0.metric.displayName): \($0.errorDescription)" }
                    .joined(separator: "\n")
                let failure = SyncFailure.partial(
                    successes: stats.newCount,
                    failures: queryIssues.count,
                    message: queryMessage
                )
                record.status = .partialFailure
                record.applyFailure(failure)
                result.successCount = 1 // partial success still counts as a successful delivery
                result.errors.append(SyncDestinationError(
                    destinationName: config.name,
                    errorDescription: queryMessage
                ))
                logger.warning("Sync partially succeeded for \(config.name): \(queryMessage)")
            }
        } catch {
            let failure = destination.classifyError(error)
            record.applyFailure(failure)
            record.duration = Date().timeIntervalSince(startTime)

            // Deferred outcomes (locked / offline / ran-out-of-time) are not real
            // failures — they're informational and the next sync will retry the
            // same window. Don't increment failCount for them.
            if case .deferred = failure {
                record.status = .deferred
                result.deferredCount = 1
                result.errors.append(SyncDestinationError(
                    destinationName: config.name,
                    errorDescription: failure.displayMessage
                ))
                logger.info("Sync deferred for \(config.name) [\(failure.categoryRaw)]: \(failure.displayMessage)")
            } else {
                record.status = .failure
                result.failCount = 1
                result.errors.append(SyncDestinationError(
                    destinationName: config.name,
                    errorDescription: failure.displayMessage
                ))
                logger.error("Sync failed for \(config.name) [\(failure.categoryRaw)]: \(failure.displayMessage)")
            }
        }

        return result
    }

    // MARK: Health Data Queries

    /// Aggregated query output for a single destination.
    private struct QueryOutcome {
        var dataPoints: [HealthDataPoint]
        var issues: [HealthMetricQueryIssue]
        var newAnchors: [HealthMetricType: Data]
    }

    /// Queries HealthKit for all enabled metrics on a destination.
    ///
    /// - Discrete metrics (heart rate, sleep, etc.) use HKAnchoredObjectQuery
    ///   with a per-(destination, metric) stored anchor. New anchors returned
    ///   here are NOT yet persisted — the caller persists them only after a
    ///   successful destination delivery to prevent gaps.
    /// - Cumulative metrics (steps, energy) keep using HKStatisticsCollectionQuery
    ///   with a short rolling window because aggregations can change retroactively.
    private func queryHealthData(
        for config: DestinationConfig,
        destination: any SyncDestination,
        healthKitReader: any HealthKitReading,
        modelContext: ModelContext
    ) async -> QueryOutcome {
        let now = Date.now
        let cumulativeWindow = destination.cumulativeQueryWindow(
            lastSyncedAt: config.lastSyncedAt,
            needsFullSync: config.needsFullSync,
            now: now
        ) ?? defaultCumulativeWindow(now: now)

        let cumulativeMetrics = config.enabledMetrics.filter(\.isCumulative)
        let discreteMetrics = config.enabledMetrics.subtracting(cumulativeMetrics)

        var dataPoints: [HealthDataPoint] = []
        var queryIssues: [HealthMetricQueryIssue] = []
        var newAnchors: [HealthMetricType: Data] = [:]

        if !discreteMetrics.isEmpty {
            let anchors = config.needsFullSync
                ? [:]
                : loadAnchors(for: config, metrics: discreteMetrics, modelContext: modelContext)
            let fallbackStart = config.needsFullSync
                ? destination.queryWindow(lastSyncedAt: config.lastSyncedAt, needsFullSync: true, now: now).start
                : Calendar.current.date(byAdding: .day, value: -Self.initialFallbackLookbackDays, to: now) ?? now

            let result = await healthKitReader.queryData(
                for: discreteMetrics,
                anchors: anchors,
                fallbackStart: fallbackStart,
                end: now
            )
            dataPoints.append(contentsOf: result.dataPoints)
            queryIssues.append(contentsOf: result.issues)
            newAnchors.merge(result.newAnchors) { _, new in new }
        }

        if !cumulativeMetrics.isEmpty {
            let aggregated = await healthKitReader.queryDailyStatistics(
                for: cumulativeMetrics,
                from: cumulativeWindow.start,
                to: cumulativeWindow.end
            )
            dataPoints.append(contentsOf: aggregated.dataPoints)
            queryIssues.append(contentsOf: aggregated.issues)
        }

        return QueryOutcome(dataPoints: dataPoints, issues: queryIssues, newAnchors: newAnchors)
    }

    /// Default cumulative query window when the destination doesn't supply one.
    /// Last 3 days catches retroactive aggregation changes from late-arriving samples.
    private func defaultCumulativeWindow(now: Date) -> QueryWindow {
        let start = Calendar.current.date(byAdding: .day, value: -Self.cumulativeRollingLookbackDays, to: now) ?? now
        return QueryWindow(start: start, end: now)
    }

    // MARK: Anchor Persistence

    /// Loads stored anchor blobs for the given (destination, metrics) pairs from SwiftData.
    private func loadAnchors(
        for config: DestinationConfig,
        metrics: Set<HealthMetricType>,
        modelContext: ModelContext
    ) -> [HealthMetricType: Data] {
        let destinationID = config.id
        let metricRawValues = Set(metrics.map(\.rawValue))
        let descriptor = FetchDescriptor<MetricSyncAnchor>(
            predicate: #Predicate<MetricSyncAnchor> { anchor in
                anchor.destinationID == destinationID
                    && metricRawValues.contains(anchor.metricRawValue)
            }
        )

        guard let stored = try? modelContext.fetch(descriptor) else { return [:] }

        var anchors: [HealthMetricType: Data] = [:]
        for record in stored {
            if let metric = record.metric {
                anchors[metric] = record.anchorData
            }
        }
        return anchors
    }

    /// Inserts or updates `MetricSyncAnchor` rows for the metrics that succeeded.
    /// Caller is responsible for `try modelContext.save()` afterwards.
    private func persistAnchors(
        _ anchors: [HealthMetricType: Data],
        for config: DestinationConfig,
        modelContext: ModelContext
    ) {
        guard !anchors.isEmpty else { return }
        let destinationID = config.id

        for (metric, data) in anchors {
            let metricRaw = metric.rawValue
            let descriptor = FetchDescriptor<MetricSyncAnchor>(
                predicate: #Predicate<MetricSyncAnchor> { anchor in
                    anchor.destinationID == destinationID
                        && anchor.metricRawValue == metricRaw
                }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.anchorData = data
                existing.lastUpdated = .now
            } else {
                let record = MetricSyncAnchor(destinationID: config.id, metric: metric, anchorData: data)
                modelContext.insert(record)
            }
        }
    }

    // MARK: Bulk Defer

    /// Records a deferred SyncRecord per applicable destination and returns a
    /// SyncResult reflecting the deferred state. Used when the whole run is
    /// blocked at the gate (locked device, offline) before any destination work
    /// has started.
    private func makeDeferredResult(
        for destinations: [DestinationConfig],
        modelContext: ModelContext,
        isAutomatic: Bool,
        isBackground: Bool,
        reason: SyncFailure.DeferReason,
        message: String,
        startTime: Date
    ) -> SyncResult {
        var deferredCount = 0
        var errors: [SyncDestinationError] = []

        for config in destinations where !config.enabledMetrics.isEmpty {
            // Automatic syncs skip recently-synced destinations entirely.
            if isAutomatic,
               !config.needsFullSync,
               let lastSynced = config.lastSyncedAt,
               Date.now.timeIntervalSince(lastSynced) < config.syncFrequency.timeInterval * 0.9
            {
                continue
            }
            let record = makeRecord(for: config, startTime: startTime, isBackground: isBackground, modelContext: modelContext)
            let failure = SyncFailure.deferred(reason: reason, message: message)
            record.status = .deferred
            record.applyFailure(failure)
            record.duration = Date().timeIntervalSince(startTime)
            deferredCount += 1
            errors.append(SyncDestinationError(
                destinationName: config.name,
                errorDescription: message
            ))
        }

        try? modelContext.save()

        return SyncResult(
            dataPointCount: 0,
            processedDataPointCount: 0,
            successfulDestinations: 0,
            failedDestinations: 0,
            deferredDestinations: deferredCount,
            duration: Date().timeIntervalSince(startTime),
            errors: errors
        )
    }

    /// Inserts a fresh `.inProgress` SyncRecord for a destination.
    private func makeRecord(
        for config: DestinationConfig,
        startTime: Date,
        isBackground: Bool,
        modelContext: ModelContext
    ) -> SyncRecord {
        let record = SyncRecord(
            destinationName: config.name,
            destinationID: config.id,
            timestamp: startTime,
            status: .inProgress,
            isBackgroundSync: isBackground
        )
        modelContext.insert(record)
        return record
    }

    // MARK: Record Retention

    /// Deletes sync records older than 30 days to prevent unbounded store growth.
    private func pruneOldSyncRecords(modelContext: ModelContext) {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let descriptor = FetchDescriptor<SyncRecord>(
            predicate: #Predicate<SyncRecord> { $0.timestamp < thirtyDaysAgo }
        )

        do {
            let oldRecords = try modelContext.fetch(descriptor)
            guard !oldRecords.isEmpty else { return }
            for record in oldRecords {
                modelContext.delete(record)
            }
            try modelContext.save()
            logger.info("Pruned \(oldRecords.count) sync records older than 30 days")
        } catch {
            logger.error("Failed to prune old sync records: \(error.localizedDescription)")
        }
    }
}

// MARK: - AlwaysReachableNetworkMonitor

/// Test-only `NetworkPathMonitoring` that always reports reachable.
/// Used as the default in `SyncEngine.init(healthKitReader:...)` so existing
/// tests don't need to know about reachability.
struct AlwaysReachableNetworkMonitor: NetworkPathMonitoring {
    var isReachable: Bool {
        true
    }
}
