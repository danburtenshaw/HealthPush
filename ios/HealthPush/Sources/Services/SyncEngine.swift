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
final class SyncEngine: Observable {
    // MARK: Properties

    private let logger = Logger(subsystem: "app.healthpush", category: "SyncEngine")
    private var healthKitManager: HealthKitManager?
    private let networkService = NetworkService()

    // MARK: Initialization

    init() {
        do {
            healthKitManager = try HealthKitManager()
        } catch {
            logger.warning("HealthKit not available: \(error.localizedDescription)")
            healthKitManager = nil
        }
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
            return SyncResult(
                dataPointCount: 0,
                successfulDestinations: 0,
                failedDestinations: 0,
                duration: Date().timeIntervalSince(startTime),
                errors: []
            )
        }

        guard let healthKitManager else {
            logger.error("HealthKit not available")
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

            // Determine lookback window based on destination type.
            // Home Assistant only needs data since last sync (sends latest value per metric).
            // S3 always re-syncs 3 days to catch delayed Apple Watch data —
            // the merge layer deduplicates by UUID so re-syncing is safe and idempotent.
            let lookbackDate: Date = switch config.destinationType {
            case .homeAssistant:
                if let lastSynced = config.lastSyncedAt {
                    lastSynced
                } else {
                    Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now
                }
            case .s3:
                if config.needsFullSync {
                    // Full sync: query from the configured start date
                    config.resolvedSyncStartDate
                } else {
                    // Incremental: 3-day lookback for delayed Apple Watch data
                    Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
                }
            }

            // Split metrics: cumulative use statistics aggregation, discrete use raw samples
            let cumulativeMetrics = config.enabledMetrics.filter(\.isCumulative)
            let discreteMetrics = config.enabledMetrics.subtracting(cumulativeMetrics)

            var dataPoints: [HealthDataPoint] = []
            var queryIssues: [HealthMetricQueryIssue] = []

            // Query discrete metrics with the destination's standard lookback
            if !discreteMetrics.isEmpty {
                let discrete = await healthKitManager.queryData(
                    for: discreteMetrics,
                    from: lookbackDate,
                    to: .now
                )
                dataPoints.append(contentsOf: discrete.dataPoints)
                queryIssues.append(contentsOf: discrete.issues)
            }

            // Query cumulative metrics using HKStatisticsCollectionQuery for deduplicated totals
            if !cumulativeMetrics.isEmpty {
                // For HA, query from start-of-today so the value represents the
                // full day's total ("8,432 steps today"), not a partial delta.
                // For S3, use the same lookback as discrete metrics.
                let cumulativeLookback: Date = switch config.destinationType {
                case .homeAssistant:
                    Calendar.current.startOfDay(for: .now)
                case .s3:
                    lookbackDate
                }

                let aggregated = await healthKitManager.queryDailyStatistics(
                    for: cumulativeMetrics,
                    from: cumulativeLookback,
                    to: .now
                )
                dataPoints.append(contentsOf: aggregated.dataPoints)
                queryIssues.append(contentsOf: aggregated.issues)
            }

            logger.info("Queried \(dataPoints.count) data points for \(config.name) (since \(lookbackDate))")

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

                let stats: SyncStats
                switch config.destinationType {
                case .homeAssistant:
                    let destination = try HomeAssistantDestination(
                        config: config,
                        networkService: networkService
                    )
                    stats = try await destination.sync(data: dataPoints, onProgress: progressCallback)
                case .s3:
                    let destination = try S3Destination(config: config)
                    stats = try await destination.sync(data: dataPoints, onProgress: progressCallback)
                }

                totalDataPoints += stats.newCount
                record.dataPointCount = stats.newCount
                record.duration = Date().timeIntervalSince(startTime)

                if queryIssues.isEmpty {
                    record.status = .success
                    config.lastSyncedAt = .now
                    if config.needsFullSync {
                        config.needsFullSync = false
                    }
                    successCount += 1
                    logger.info("Synced \(dataPoints.count) points to \(config.name)")
                } else {
                    let queryMessage = queryIssues
                        .sorted { $0.metric.rawValue < $1.metric.rawValue }
                        .map { "\($0.metric.displayName): \($0.errorDescription)" }
                        .joined(separator: "\n")
                    record.status = .partialFailure
                    record.errorMessage = queryMessage
                    failCount += 1
                    errors.append(SyncDestinationError(
                        destinationName: config.name,
                        errorDescription: queryMessage
                    ))
                    logger.error("Sync partially failed for \(config.name): \(queryMessage)")
                }
            } catch {
                record.status = .failure
                record.errorMessage = error.localizedDescription
                record.duration = Date().timeIntervalSince(startTime)
                failCount += 1
                errors.append(SyncDestinationError(destinationName: config.name, errorDescription: error.localizedDescription))

                logger.error("Sync failed for \(config.name): \(error.localizedDescription)")
            }
        }

        // Save sync records and updated destination configs
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save sync records: \(error.localizedDescription)")
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.info("Sync completed in \(String(format: "%.1f", duration))s: \(successCount) succeeded, \(failCount) failed")

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
        await healthKitManager?.enableBackgroundDelivery(for: metrics, onUpdate: onUpdate)
    }

    /// Requests HealthKit authorization for the given metrics.
    /// - Parameter metrics: The health metrics to authorize.
    func requestHealthKitAuthorization(for metrics: Set<HealthMetricType>) async throws {
        guard let healthKitManager else {
            throw SyncError.healthKitUnavailable
        }
        try await healthKitManager.requestAuthorization(for: metrics)
    }

    /// Resets all HealthKit anchors, forcing a full re-sync next time.
    func resetAnchors() async {
        await healthKitManager?.resetAnchors()
    }
}
