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
    let dataPointCount: Int
    let successfulDestinations: Int
    let failedDestinations: Int
    let duration: TimeInterval
    let errors: [SyncDestinationError]
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

    /// Factory closure that creates a ``SyncDestination`` from a config.
    /// Defaults to ``DestinationManager/makeDestination(for:networkService:)``.
    private let destinationFactory: @MainActor (DestinationConfig, NetworkService) throws -> any SyncDestination

    // MARK: Initialization

    /// Creates a sync engine that auto-discovers HealthKit.
    ///
    /// Attempts to create a ``HealthKitManager``. If HealthKit is unavailable on the
    /// device, the reader is set to `nil` and syncs will report a graceful error.
    init() {
        networkService = NetworkService()
        destinationFactory = DestinationManager.makeDestination
        do {
            healthKitReader = try HealthKitManager()
        } catch {
            logger.warning("HealthKit not available: \(error.localizedDescription)")
            healthKitReader = nil
        }
    }

    /// Creates a sync engine with injected dependencies (for testing).
    ///
    /// - Parameters:
    ///   - healthKitReader: A ``HealthKitReading`` implementation, or `nil` to simulate unavailability.
    ///   - networkService: The network service for destination requests.
    ///   - destinationFactory: Closure to create destinations from configs. Defaults to ``DestinationManager/makeDestination(for:networkService:)``.
    init(
        healthKitReader: (any HealthKitReading)?,
        networkService: NetworkService = NetworkService(),
        destinationFactory: @MainActor @escaping (DestinationConfig, NetworkService) throws -> any SyncDestination = DestinationManager.makeDestination
    ) {
        self.networkService = networkService
        self.healthKitReader = healthKitReader
        self.destinationFactory = destinationFactory
    }

    // MARK: Sync Operations

    /// Performs a full sync for all enabled destinations.
    /// - Parameters:
    ///   - modelContext: The SwiftData model context for persistence.
    ///   - isBackground: Whether this is a background sync.
    /// - Returns: The sync result.
    /// Progress callback: (destinationName, fractionComplete)
    typealias ProgressHandler = @MainActor (String, Double) -> Void

    func performSync(
        modelContext: ModelContext,
        isBackground: Bool = false,
        onProgress: ProgressHandler? = nil
    ) async -> SyncResult {
        let syncState = signposter.beginInterval("performSync")
        let startTime = Date()
        logger.info("Starting sync (background: \(isBackground))")

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
                successfulDestinations: 0,
                failedDestinations: 0,
                duration: Date().timeIntervalSince(startTime),
                errors: []
            )
        }

        guard let healthKitReader else {
            logger.error("HealthKit not available")
            signposter.endInterval("performSync", syncState)
            return SyncResult(
                dataPointCount: 0,
                successfulDestinations: 0,
                failedDestinations: 0,
                duration: Date().timeIntervalSince(startTime),
                errors: [SyncDestinationError(
                    destinationName: "HealthKit",
                    errorDescription: SyncError.healthKitUnavailable.localizedDescription
                )]
            )
        }

        // Sync each destination independently with its own query window
        var successCount = 0
        var failCount = 0
        var totalDataPoints = 0
        var errors: [SyncDestinationError] = []

        for config in destinations {
            // Skip destinations with no enabled metrics — nothing to sync.
            if config.enabledMetrics.isEmpty {
                logger.info("Skipping \(config.name) — no health metrics enabled")
                continue
            }

            // In background mode, skip destinations that were synced recently enough
            // per their own frequency. Manual "Sync Now" always syncs everything.
            if isBackground,
               !config.needsFullSync,
               let lastSynced = config.lastSyncedAt,
               Date.now.timeIntervalSince(lastSynced) < config.syncFrequency.timeInterval * 0.9
            {
                logger.info("Skipping \(config.name) — last synced \(lastSynced), interval not yet elapsed")
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

            let (rawDataPoints, queryIssues) = await queryHealthData(
                for: config,
                destination: destination,
                healthKitReader: healthKitReader
            )

            // Strip source metadata (app name, bundle ID) when the user has opted out.
            let dataPoints = config.includeSourceMetadata
                ? rawDataPoints
                : rawDataPoints.map { $0.strippingSourceMetadata() }

            logger.info("Queried \(dataPoints.count) data points for \(config.name)")

            let result = await syncDestination(
                config: config,
                destination: destination,
                dataPoints: dataPoints,
                queryIssues: queryIssues,
                startTime: startTime,
                modelContext: modelContext,
                isBackground: isBackground,
                onProgress: onProgress
            )
            totalDataPoints += result.dataPointCount
            successCount += result.successCount
            failCount += result.failCount
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
        logger.info("Sync completed in \(String(format: "%.1f", duration))s: \(successCount) succeeded, \(failCount) failed")

        signposter.endInterval("performSync", syncState)
        return SyncResult(
            dataPointCount: totalDataPoints,
            successfulDestinations: successCount,
            failedDestinations: failCount,
            duration: duration,
            errors: errors
        )
    }

    /// Enables HealthKit background delivery for the given metrics.
    ///
    /// Delegates to the internal `HealthKitManager` to register observer queries.
    /// When new health data arrives, the `onUpdate` callback is invoked.
    /// - Parameters:
    ///   - metrics: The health metrics to observe.
    ///   - onUpdate: Callback when new data is available.
    func enableBackgroundDelivery(
        for metrics: Set<HealthMetricType>,
        onUpdate: @escaping @Sendable () async -> Void
    ) async {
        await healthKitReader?.enableBackgroundDelivery(for: metrics, onUpdate: onUpdate)
    }

    /// Requests HealthKit authorization for the given metrics.
    /// - Parameter metrics: The health metrics to authorize.
    func requestHealthKitAuthorization(for metrics: Set<HealthMetricType>) async throws {
        guard let healthKitReader else {
            throw SyncError.healthKitUnavailable
        }
        try await healthKitReader.requestAuthorization(for: metrics)
    }

    /// Resets all HealthKit anchors, forcing a full re-sync next time.
    func resetAnchors() async {
        await healthKitReader?.resetAnchors()
    }

    // MARK: Single-Destination Sync

    /// Result of syncing a single destination, used to aggregate into the overall SyncResult.
    private struct DestinationSyncResult {
        var dataPointCount: Int = 0
        var successCount: Int = 0
        var failCount: Int = 0
        var errors: [SyncDestinationError] = []
    }

    /// Pushes data to a single destination, records the outcome, and returns aggregate counts.
    private func syncDestination(
        config: DestinationConfig,
        destination: any SyncDestination,
        dataPoints: [HealthDataPoint],
        queryIssues: [HealthMetricQueryIssue],
        startTime: Date,
        modelContext: ModelContext,
        isBackground: Bool,
        onProgress: ProgressHandler?
    ) async -> DestinationSyncResult {
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
            record.dataPointCount = stats.newCount
            record.duration = Date().timeIntervalSince(startTime)

            if queryIssues.isEmpty {
                record.status = .success
                config.lastSyncedAt = .now
                if config.needsFullSync {
                    config.needsFullSync = false
                }
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
                result.failCount = 1
                result.errors.append(SyncDestinationError(
                    destinationName: config.name,
                    errorDescription: queryMessage
                ))
                logger.error("Sync partially failed for \(config.name): \(queryMessage)")
            }
        } catch {
            let failure = destination.classifyError(error)
            record.status = .failure
            record.applyFailure(failure)
            record.duration = Date().timeIntervalSince(startTime)
            result.failCount = 1
            result.errors.append(SyncDestinationError(
                destinationName: config.name,
                errorDescription: failure.displayMessage
            ))
            logger.error("Sync failed for \(config.name) [\(failure.categoryRaw)]: \(failure.displayMessage)")
        }

        return result
    }

    // MARK: Health Data Queries

    /// Queries HealthKit for all enabled metrics on a destination, using the destination's
    /// preferred query windows for discrete and cumulative metric types.
    private func queryHealthData(
        for config: DestinationConfig,
        destination: any SyncDestination,
        healthKitReader: any HealthKitReading
    ) async -> (dataPoints: [HealthDataPoint], issues: [HealthMetricQueryIssue]) {
        let now = Date.now
        let discreteWindow = destination.queryWindow(
            lastSyncedAt: config.lastSyncedAt,
            needsFullSync: config.needsFullSync,
            now: now
        )
        let cumulativeWindow = destination.cumulativeQueryWindow(
            lastSyncedAt: config.lastSyncedAt,
            now: now
        ) ?? discreteWindow

        let cumulativeMetrics = config.enabledMetrics.filter(\.isCumulative)
        let discreteMetrics = config.enabledMetrics.subtracting(cumulativeMetrics)

        var dataPoints: [HealthDataPoint] = []
        var queryIssues: [HealthMetricQueryIssue] = []

        if !discreteMetrics.isEmpty {
            let discrete = await healthKitReader.queryData(
                for: discreteMetrics,
                from: discreteWindow.start,
                to: discreteWindow.end
            )
            dataPoints.append(contentsOf: discrete.dataPoints)
            queryIssues.append(contentsOf: discrete.issues)
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

        return (dataPoints, queryIssues)
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
