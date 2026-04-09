import BackgroundTasks
import Foundation
import os

// MARK: - BackgroundSyncScheduler

/// Manages BGTaskScheduler registration, scheduling, and execution for background syncs.
///
/// This class registers two task types:
/// - `BGAppRefreshTask`: lightweight sync for frequent updates.
/// - `BGProcessingTask`: heavier sync for larger data transfers.
@MainActor
final class BackgroundSyncScheduler {
    // MARK: Constants

    static let refreshTaskIdentifier = "app.healthpush.sync.refresh"
    static let processingTaskIdentifier = "app.healthpush.sync.processing"

    // MARK: Properties

    private let logger = Logger(subsystem: "app.healthpush", category: "BackgroundSync")

    /// The callback that performs the actual sync work. Set by the app on launch.
    private var syncHandler: (@Sendable () async -> Bool)?

    /// Debounce task for observer-triggered syncs.
    private var pendingObserverSync: Task<Void, Never>?

    /// Observable application state — the single source of truth for `isSyncing`.
    /// Set via ``configure(appState:)`` before the first sync.
    private var appState: AppState?

    /// The last frequency used to schedule tasks. Used by task handlers to
    /// re-schedule with the correct interval (instead of reading a stale global default).
    private(set) var lastScheduledFrequency: SyncFrequency = .oneHour

    // MARK: Singleton

    static let shared = BackgroundSyncScheduler()

    private init() { }

    // MARK: Configuration

    /// Provides the shared `AppState` so the scheduler can use its `isSyncing` flag
    /// as the single source of truth for sync-in-progress gating.
    /// - Parameter appState: The application-wide observable state.
    func configure(appState: AppState) {
        self.appState = appState
    }

    /// Whether a sync is currently in progress, delegated to ``AppState/isSyncing``.
    private var isSyncing: Bool {
        get { appState?.isSyncing ?? false }
        set { appState?.isSyncing = newValue }
    }

    // MARK: Registration

    /// Registers background task handlers with the system.
    /// Must be called before the end of `application(_:didFinishLaunchingWithOptions:)`.
    /// - Parameter handler: An async closure that performs the sync and returns success.
    func registerTasks(syncHandler: @escaping @Sendable () async -> Bool) {
        self.syncHandler = syncHandler

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                await self?.handleRefreshTask(bgTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let bgTask = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await self?.handleProcessingTask(bgTask)
            }
        }

        logger.info("Background tasks registered")
    }

    // MARK: Scheduling

    /// Schedules the next background app refresh task.
    /// - Parameter frequency: How often to schedule the task.
    func scheduleRefreshTask(frequency: SyncFrequency) {
        lastScheduledFrequency = frequency
        UserDefaults.standard.set(frequency.rawValue, forKey: "scheduled_sync_frequency")
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: frequency.timeInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            if let earliest = request.earliestBeginDate {
                UserDefaults.standard.set(earliest.timeIntervalSince1970, forKey: "next_scheduled_sync_time")
            }
            logger.info("Scheduled refresh task for \(frequency.displayName)")
        } catch {
            logger.error("Failed to schedule refresh task: \(error.localizedDescription)")
        }
    }

    /// Schedules a background processing task for heavier sync operations.
    /// - Parameter frequency: How often to schedule the task.
    func scheduleProcessingTask(frequency: SyncFrequency) {
        lastScheduledFrequency = frequency
        UserDefaults.standard.set(frequency.rawValue, forKey: "scheduled_sync_frequency")
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: frequency.timeInterval)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled processing task for \(frequency.displayName)")
        } catch {
            logger.error("Failed to schedule processing task: \(error.localizedDescription)")
        }
    }

    /// Cancels all pending background tasks.
    func cancelAllTasks() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        logger.info("All background tasks cancelled")
    }

    // MARK: Observer Handling

    /// Called when an HKObserverQuery fires. Debounces rapid successive calls
    /// (e.g., Apple Watch dumping multiple metric types at once) into a single sync.
    func handleObserverUpdate() {
        pendingObserverSync?.cancel()
        pendingObserverSync = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            guard !isSyncing else {
                logger.info("Observer sync skipped — another sync is in progress")
                return
            }

            logger.info("Observer-triggered sync starting (debounced)")
            isSyncing = true
            let success = await syncHandler?() ?? false
            isSyncing = false
            if success {
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "last_sync_time")
            }
            logger.info("Observer-triggered sync completed with success: \(success)")
        }
    }

    // MARK: Task Handling

    private func handleRefreshTask(_ task: BGAppRefreshTask) async {
        logger.info("Starting background refresh task")

        // Schedule the next refresh immediately so we keep getting called
        scheduleRefreshTask(frequency: lastScheduledFrequency)

        guard !isSyncing else {
            logger.info("Refresh task skipped — another sync is in progress")
            task.setTaskCompleted(success: true)
            return
        }

        isSyncing = true
        let syncTask = Task {
            await syncHandler?() ?? false
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        let success = await syncTask.value
        isSyncing = false
        task.setTaskCompleted(success: success)
        logger.info("Background refresh task completed with success: \(success)")
    }

    private func handleProcessingTask(_ task: BGProcessingTask) async {
        logger.info("Starting background processing task")

        scheduleProcessingTask(frequency: lastScheduledFrequency)

        guard !isSyncing else {
            logger.info("Processing task skipped — another sync is in progress")
            task.setTaskCompleted(success: true)
            return
        }

        isSyncing = true
        let syncTask = Task {
            await syncHandler?() ?? false
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        let success = await syncTask.value
        isSyncing = false
        task.setTaskCompleted(success: success)
        logger.info("Background processing task completed with success: \(success)")
    }
}
