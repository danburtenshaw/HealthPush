import BackgroundTasks
import Foundation
import os
import UIKit

// MARK: - BackgroundSyncScheduler

/// Manages BGTaskScheduler registration, scheduling, and execution for background syncs.
///
/// ## Strategy
///
/// HealthPush uses **two complementary delivery paths**:
///
/// 1. **HKObserverQuery + `.immediate` background delivery** — the primary path.
///    HealthKit wakes the app within seconds of new samples being written
///    (Apple Watch sync, manual entry, etc.), and the scheduler debounces those
///    notifications into a single sync attempt.
/// 2. **`BGProcessingTask`** — a periodic safety net. Submitted at the user's
///    chosen interval as a hint; iOS opportunistically dispatches it when the
///    device is idle and conditions allow. We use processing (not refresh)
///    because it gives us several minutes instead of ~30 seconds, which fits
///    multi-destination uploads with anchored deltas.
///
/// The scheduler defers — never fails — when:
/// - The device is locked (protected data unavailable). HealthKit's data store
///   is encrypted on lock, so background reads return empty.
/// - The network is unreachable (only matters for observer-triggered syncs;
///   BGProcessingTask sets `requiresNetworkConnectivity` so the system holds
///   the task until network is back).
@MainActor
final class BackgroundSyncScheduler {
    // MARK: Constants

    /// Identifier for the periodic safety-net `BGProcessingTask`. Must match
    /// `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let processingTaskIdentifier = "app.healthpush.sync.processing"

    /// Legacy refresh-task identifier kept registered as a polite no-op so
    /// pending refresh requests scheduled by older builds drain cleanly without
    /// crashing the app. Future builds can remove the registration once
    /// existing installs have rotated through.
    static let refreshTaskIdentifier = "app.healthpush.sync.refresh"

    /// Estimated execution budget for `BGProcessingTask`. Apple gives "several
    /// minutes" — we use 3 minutes as a conservative cutoff so we abort cleanly
    /// before the system's expirationHandler fires.
    private static let processingTaskBudget: TimeInterval = 3 * 60

    // MARK: Properties

    private let logger = Logger(subsystem: "app.healthpush", category: "BackgroundSync")

    /// Schedules / cancels / queries pending BG tasks. Wraps `BGTaskScheduler`
    /// in production; tests inject a fake.
    private let taskScheduler: any BGTaskScheduling

    /// Reports `isProtectedDataAvailable` and notifies on unlock.
    private let protectedDataMonitor: any ProtectedDataMonitoring

    /// The callback that performs the actual sync work.
    /// - `deadline`: cutoff for the run, or nil for observer syncs that have no
    ///   hard budget.
    /// - `isBackground`: whether the app was actually in the background when the
    ///   sync started. BGProcessingTask is always true; observer syncs check
    ///   `UIApplication.applicationState` at sync time so a sync triggered by
    ///   opening the app is tagged foreground.
    private var syncHandler: (@Sendable (_ deadline: Date?, _ isBackground: Bool) async -> Bool)?

    /// Debounce task for observer-triggered syncs.
    private var pendingObserverSync: Task<Void, Never>?

    /// When true, observer-triggered syncs are suppressed (e.g. during initial
    /// observer registration, which fires all queries immediately).
    private var suppressObserverSyncs = false

    /// Observable application state — the single source of truth for `isSyncing`.
    /// Set via ``configure(appState:)`` before the first sync.
    private var appState: AppState?

    /// The last frequency used to schedule tasks. Used by task handlers to
    /// re-schedule with the correct interval after work completes.
    private(set) var lastScheduledFrequency: SyncFrequency = .oneHour

    // MARK: Singleton

    static let shared = BackgroundSyncScheduler()

    private init(
        taskScheduler: any BGTaskScheduling = BGTaskScheduler.shared,
        protectedDataMonitor: any ProtectedDataMonitoring = ProtectedDataMonitor.shared
    ) {
        self.taskScheduler = taskScheduler
        self.protectedDataMonitor = protectedDataMonitor
    }

    // MARK: Test seam

    /// Test-only initializer that lets a test substitute the BG scheduler and
    /// protected-data monitor. Production code uses ``shared``.
    static func makeForTesting(
        taskScheduler: any BGTaskScheduling,
        protectedDataMonitor: any ProtectedDataMonitoring
    ) -> BackgroundSyncScheduler {
        BackgroundSyncScheduler(
            taskScheduler: taskScheduler,
            protectedDataMonitor: protectedDataMonitor
        )
    }

    // MARK: Configuration

    /// Provides the shared `AppState` so the scheduler can use its `isSyncing` flag
    /// as the single source of truth for sync-in-progress gating.
    func configure(appState: AppState) {
        self.appState = appState
    }

    /// Whether a sync is currently in progress.
    private var isSyncing: Bool {
        get { appState?.isSyncing ?? false }
        set { appState?.isSyncing = newValue }
    }

    // MARK: Registration

    /// Registers background task handlers with the system.
    /// Must be called before the end of `application(_:didFinishLaunchingWithOptions:)`.
    /// - Parameter syncHandler: An async closure that performs the sync. Receives
    ///   the optional `deadline` (the BGTask's estimated end time) and
    ///   `isBackground` (true when iOS actually woke the app in the background;
    ///   false when the observer fired while the app was open). Returns whether
    ///   the run completed successfully.
    func registerTasks(syncHandler: @escaping @Sendable (_ deadline: Date?, _ isBackground: Bool) async -> Bool) {
        self.syncHandler = syncHandler

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let bgTask = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await self?.handleProcessingTask(bgTask)
            }
        }

        // Drain legacy refresh-task requests scheduled by older builds. The
        // handler completes immediately so iOS doesn't terminate the app for an
        // unhandled task. After one OS cycle these will stop being submitted.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                task.setTaskCompleted(success: true)
            }
        }

        logger.info("Background tasks registered")
    }

    // MARK: Scheduling

    /// Schedules the periodic safety-net processing task at the user's chosen
    /// interval. iOS treats `earliestBeginDate` as a hint, not a guarantee —
    /// the task may run later (or not at all if the device is rarely used). The
    /// HKObserverQuery push path is what delivers timely syncs; this is the
    /// fallback for periods between observer events.
    ///
    /// Idempotent: if a request is already pending, this updates the cached
    /// frequency without re-submitting (re-submitting resets the clock and is
    /// the chief cause of "every 15 min" turning into "every random interval").
    func scheduleProcessingTask(frequency: SyncFrequency, force: Bool = false) async {
        lastScheduledFrequency = frequency
        UserDefaults.standard.set(frequency.rawValue, forKey: "scheduled_sync_frequency")

        if !force {
            let pending = await taskScheduler.pendingTaskIdentifiers()
            if pending.contains(Self.processingTaskIdentifier) {
                logger.debug("Processing task already scheduled — not resubmitting")
                return
            }
        }

        submitProcessingTask(earliestBeginDate: Date(timeIntervalSinceNow: frequency.timeInterval))
    }

    /// Submits a one-shot processing task to retry sooner than the normal
    /// cadence. Used after a deferred-out-of-time run so we pick the work back
    /// up promptly instead of waiting for the next scheduled interval.
    func scheduleQuickRetry(after delay: TimeInterval = 5 * 60) {
        taskScheduler.cancelAllTaskRequests()
        submitProcessingTask(earliestBeginDate: Date(timeIntervalSinceNow: delay))
        logger.info("Scheduled quick retry in \(Int(delay))s")
    }

    /// Cancels every pending background task request.
    func cancelAllTasks() {
        taskScheduler.cancelAllTaskRequests()
        logger.info("All background tasks cancelled")
    }

    private func submitProcessingTask(earliestBeginDate: Date) {
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try taskScheduler.submit(request)
            UserDefaults.standard.set(earliestBeginDate.timeIntervalSince1970, forKey: "next_scheduled_sync_time")
            logger.info("Scheduled processing task no earlier than \(earliestBeginDate)")
        } catch {
            logger.error("Failed to schedule processing task: \(error.localizedDescription)")
        }
    }

    // MARK: Observer Handling

    /// Temporarily suppresses observer-triggered syncs. Use this around
    /// `enableBackgroundDelivery` calls so the initial observer fire storm
    /// during registration doesn't trigger an immediate sync.
    func withObserversSuppressed(_ work: () async -> Void) async {
        suppressObserverSyncs = true
        await work()
        try? await Task.sleep(for: .seconds(4))
        suppressObserverSyncs = false
    }

    /// Called when an HKObserverQuery fires. Debounces rapid successive calls
    /// (e.g., Apple Watch dumping multiple metric types at once) into a single sync.
    func handleObserverUpdate() {
        guard !suppressObserverSyncs else {
            logger.info("Observer update suppressed during registration")
            return
        }

        // If the device is locked, HealthKit reads return empty. Skip the
        // attempt entirely (don't even create a SyncRecord) and queue a sync
        // for the next unlock — that's when the data actually becomes available.
        guard protectedDataMonitor.isProtectedDataAvailable else {
            logger.info("Observer-triggered sync deferred — device locked")
            armUnlockTrigger()
            return
        }

        pendingObserverSync?.cancel()
        pendingObserverSync = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }

            guard !isSyncing else {
                logger.info("Observer sync skipped — another sync is in progress")
                return
            }

            // Check application state at the moment the sync actually starts,
            // not when the observer fired — the app could have backgrounded
            // during the debounce window.
            let runningInBackground = UIApplication.shared.applicationState == .background
            logger.info("Observer-triggered sync starting (debounced, background: \(runningInBackground))")
            isSyncing = true
            // Observer syncs have no hard deadline; pass nil.
            let success = await syncHandler?(nil, runningInBackground) ?? false
            isSyncing = false
            logger.info("Observer-triggered sync completed with success: \(success)")
        }
    }

    /// Arms a one-shot listener that triggers a sync the next time protected
    /// data becomes available. Used when we couldn't run because the device
    /// was locked.
    private var unlockTriggerArmed = false

    private func armUnlockTrigger() {
        guard !unlockTriggerArmed else { return }
        unlockTriggerArmed = true
        protectedDataMonitor.onNextProtectedDataAvailable { [weak self] in
            guard let self else { return }
            unlockTriggerArmed = false
            logger.info("Device unlocked — triggering deferred sync")
            handleObserverUpdate()
        }
    }

    // MARK: Task Handling

    private func handleProcessingTask(_ task: BGProcessingTask) async {
        logger.info("Starting background processing task")
        let startTime = Date()
        let deadline = startTime.addingTimeInterval(Self.processingTaskBudget)

        // Locked device → defer cleanly. Reschedule the periodic task and arm
        // an unlock listener so we run as soon as the user authenticates. Mark
        // the BGTask as successful so iOS keeps allocating us future slots.
        guard protectedDataMonitor.isProtectedDataAvailable else {
            logger.info("Processing task deferred — device locked")
            armUnlockTrigger()
            await scheduleProcessingTask(frequency: lastScheduledFrequency, force: true)
            task.setTaskCompleted(success: true)
            return
        }

        guard !isSyncing else {
            logger.info("Processing task skipped — another sync is in progress")
            await scheduleProcessingTask(frequency: lastScheduledFrequency, force: true)
            task.setTaskCompleted(success: true)
            return
        }

        isSyncing = true
        let syncTask = Task { [weak self] () -> Bool in
            // BGProcessingTask always runs with the app in the background.
            await self?.syncHandler?(deadline, true) ?? false
        }

        task.expirationHandler = {
            // System is reclaiming our slot — cancel work in flight. URLError
            // .cancelled propagates up and is classified as `.deferred(.outOfTime)`
            // so the user doesn't see a red error.
            syncTask.cancel()
        }

        let success = await syncTask.value
        isSyncing = false

        // Reschedule from inside the handler — this is the canonical pattern.
        // Using `force: true` because the previous request just fired and we
        // want a fresh `earliestBeginDate`.
        await scheduleProcessingTask(frequency: lastScheduledFrequency, force: true)

        task.setTaskCompleted(success: success)
        logger
            .info(
                "Background processing task completed in \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s, success: \(success)"
            )
    }
}
