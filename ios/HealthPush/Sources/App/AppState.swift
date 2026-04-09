import Foundation
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - AppState

/// Observable application state shared across the entire view hierarchy.
///
/// This class tracks the current sync status, last sync time, error state,
/// and user preferences. It is annotated `@MainActor` to ensure all mutations
/// happen on the main thread for safe SwiftUI binding.
@MainActor
@Observable
final class AppState {
    // MARK: Storage

    /// The `UserDefaults` instance backing all persisted preferences.
    /// Defaults to `.standard` in production; tests inject an isolated suite.
    let defaults: UserDefaults

    // MARK: Initialization

    /// Creates an AppState backed by the given UserDefaults instance.
    /// - Parameter defaults: The defaults store. Pass a suite-scoped instance in tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasSeenOnboarding = defaults.bool(forKey: "has_seen_onboarding")
    }

    // MARK: Sync Status

    /// Whether a sync is currently in progress.
    var isSyncing = false

    /// Per-destination sync progress (0.0 to 1.0). Keyed by destination name.
    var syncProgress: [String: Double] = [:]

    /// Status text per destination during sync.
    var syncStatusText: [String: String] = [:]

    /// The result of the most recent sync, if any.
    var lastSyncResult: SyncResult?

    /// Human-readable error from the last failed operation.
    var lastError: String?

    /// Whether an error alert should be shown.
    var showingError = false

    // MARK: Timestamps

    /// When the last successful sync completed. Stored property so `@Observable` tracks changes.
    ///
    /// **Note:** This is used for background scheduling decisions (e.g., `isSyncOverdue`,
    /// `BGTaskScheduler` earliest begin dates). The Dashboard UI should derive display
    /// timestamps from per-destination `DestinationConfig.lastSyncedAt` values instead.
    var lastSyncTime: Date?

    /// The next scheduled sync time, based on the actual BGTaskScheduler earliest begin date.
    var nextSyncTime: Date? {
        let interval = defaults.double(forKey: "next_scheduled_sync_time")
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    /// Whether the scheduled sync is significantly overdue (30+ minutes past expected time).
    /// Not overdue if a sync succeeded recently (within the last frequency interval).
    var isSyncOverdue: Bool {
        guard let next = nextSyncTime else { return false }
        // If we synced recently, we're not overdue regardless of the scheduled time
        if let lastSync = lastSyncTime,
           Date.now.timeIntervalSince(lastSync) < syncFrequency.timeInterval * 1.5
        {
            return false
        }
        return Date.now > next.addingTimeInterval(30 * 60)
    }

    // MARK: User Preferences

    /// The configured sync frequency.
    var syncFrequency: SyncFrequency {
        get {
            let raw = defaults.string(forKey: "scheduled_sync_frequency")
                ?? SyncFrequency.oneHour.rawValue
            return SyncFrequency(rawValue: raw) ?? .oneHour
        }
        set {
            defaults.set(newValue.rawValue, forKey: "scheduled_sync_frequency")
        }
    }

    /// How many days of sync history to retain.
    var dataRetentionDays: Int {
        get {
            let value = defaults.integer(forKey: "data_retention_days")
            return value > 0 ? value : 30
        }
        set {
            defaults.set(newValue, forKey: "data_retention_days")
        }
    }

    /// Number of data points synced today. Persisted to UserDefaults with date tracking.
    var dataPointsSyncedToday: Int {
        get {
            let storedDate = defaults.string(forKey: "data_points_synced_date") ?? ""
            let today = Self.todayString
            if storedDate != today {
                return 0
            }
            return defaults.integer(forKey: "data_points_synced_today")
        }
        set {
            defaults.set(Self.todayString, forKey: "data_points_synced_date")
            defaults.set(newValue, forKey: "data_points_synced_today")
        }
    }

    private static var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Total number of syncs completed.
    var totalSyncsCompleted: Int {
        get { defaults.integer(forKey: "total_syncs_completed") }
        set { defaults.set(newValue, forKey: "total_syncs_completed") }
    }

    /// Whether any sync has ever delivered data points. Once true, stays true.
    /// Used to distinguish initial-setup "no data" (likely a permissions issue)
    /// from routine periodic syncs that legitimately find nothing new.
    var hasEverSyncedData: Bool {
        get { defaults.bool(forKey: "has_ever_synced_data") }
        set { defaults.set(newValue, forKey: "has_ever_synced_data") }
    }

    // MARK: HealthKit

    /// Whether a HealthKit authorization request completed without an API error.
    var healthKitAuthorized: Bool {
        get { defaults.bool(forKey: "healthkit_authorized") }
        set { defaults.set(newValue, forKey: "healthkit_authorized") }
    }

    /// Whether the welcome flow has already been shown.
    /// Backed by a stored property so `@Observable` tracks mutations and SwiftUI reacts.
    /// Initialized from the injected `defaults` in `init(defaults:)`.
    var hasSeenOnboarding: Bool = false {
        didSet { defaults.set(hasSeenOnboarding, forKey: "has_seen_onboarding") }
    }

    /// Whether the most recent sync completed with one or more issues.
    var lastSyncHadIssues: Bool {
        guard let lastSyncResult else { return false }
        return lastSyncResult.failedDestinations > 0
    }

    /// Whether the last completed sync produced zero data points and the user has
    /// never successfully synced data before. This indicates a likely permissions
    /// issue during initial setup. Once any sync has delivered data, periodic syncs
    /// that find nothing new are expected and do not trigger this warning.
    var lastSyncHadNoData: Bool {
        guard let lastSyncResult else { return false }
        guard !hasEverSyncedData else { return false }
        return lastSyncResult.dataPointCount == 0
            && lastSyncResult.failedDestinations == 0
            && lastSyncResult.successfulDestinations > 0
    }

    /// Whether Background App Refresh is available for this app.
    /// Returns `false` when the user has disabled it in system Settings or Low Power Mode is active.
    var isBackgroundRefreshAvailable: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.backgroundRefreshStatus == .available
        #else
        return true
        #endif
    }

    // MARK: Methods

    /// Records a successful sync result.
    /// - Parameter result: The sync result to record.
    func recordSyncResult(_ result: SyncResult) {
        lastSyncResult = result
        if result.successfulDestinations > 0 {
            let now = Date.now
            defaults.set(now.timeIntervalSince1970, forKey: "last_sync_time")
            lastSyncTime = now
            totalSyncsCompleted += 1
            dataPointsSyncedToday += result.dataPointCount
            if result.dataPointCount > 0 {
                hasEverSyncedData = true
            }
        }

        if result.failedDestinations == 0 {
            lastError = nil
        } else if !result.errors.isEmpty {
            let errorMessages = result.errors.map { "\($0.destinationName): \($0.errorDescription)" }
            lastError = errorMessages.joined(separator: "\n")
        }
    }

    /// Sets an error state and optionally shows an alert.
    /// - Parameters:
    ///   - message: The error message.
    ///   - showAlert: Whether to trigger the error alert.
    func setError(_ message: String, showAlert: Bool = true) {
        lastError = message
        showingError = showAlert
    }

    /// Refreshes stored properties from UserDefaults. Call when the app returns
    /// to the foreground to pick up changes made by background syncs.
    func refreshFromUserDefaults() {
        let interval = defaults.double(forKey: "last_sync_time")
        lastSyncTime = interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        hasSeenOnboarding = defaults.bool(forKey: "has_seen_onboarding")
    }

    /// Clears the current error state.
    func clearError() {
        lastError = nil
        showingError = false
    }

    /// Resets all HealthPush UserDefaults keys to factory defaults and clears in-memory state.
    /// Called as part of the full data erasure flow.
    func resetToDefaults() {
        let keys = [
            "last_sync_time",
            "next_scheduled_sync_time",
            "scheduled_sync_frequency",
            "data_retention_days",
            "data_points_synced_date",
            "data_points_synced_today",
            "total_syncs_completed",
            "has_ever_synced_data",
            "healthkit_authorized",
            "has_seen_onboarding",
            "healthkit_anchors"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }

        // Reset in-memory state
        isSyncing = false
        syncProgress = [:]
        syncStatusText = [:]
        lastSyncResult = nil
        lastSyncTime = nil
        lastError = nil
        showingError = false
        hasSeenOnboarding = false
    }

    /// Returns a formatted string for the last sync time.
    var lastSyncTimeFormatted: String {
        guard let lastSyncTime else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSyncTime, relativeTo: .now)
    }

    /// Returns a formatted string for the next sync time.
    var nextSyncTimeFormatted: String {
        guard let nextSyncTime else { return "Not scheduled" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: nextSyncTime, relativeTo: .now)
    }
}
