import Testing
import Foundation
@testable import HealthPush

// MARK: - AppStateTests

@Suite("AppState")
@MainActor
struct AppStateTests {

    // MARK: Setup

    /// Clears UserDefaults keys used by AppState before each test.
    private func cleanDefaults() {
        let keys = [
            "last_sync_time",
            "data_points_synced_today",
            "data_points_synced_date",
            "next_scheduled_sync_time",
            "sync_frequency",
            "scheduled_sync_frequency",
            "total_syncs_completed",
            "data_retention_days",
            "healthkit_authorized",
            "has_seen_onboarding"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: lastSyncTime

    @Test("refreshFromUserDefaults loads lastSyncTime from UserDefaults")
    func refreshLoadsLastSyncTime() {
        cleanDefaults()
        let state = AppState()

        let now = Date.now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "last_sync_time")
        state.refreshFromUserDefaults()

        #expect(state.lastSyncTime != nil)
        #expect(abs(state.lastSyncTime!.timeIntervalSince(now)) < 1)
    }

    @Test("refreshFromUserDefaults sets nil when no sync has occurred")
    func refreshNilWhenNoSync() {
        cleanDefaults()
        let state = AppState()

        state.refreshFromUserDefaults()

        #expect(state.lastSyncTime == nil)
    }

    // MARK: dataPointsSyncedToday

    @Test("dataPointsSyncedToday resets when date changes")
    func counterResetsAtMidnight() {
        cleanDefaults()
        // Set counter with yesterday's date
        UserDefaults.standard.set(100, forKey: "data_points_synced_today")
        UserDefaults.standard.set("1999-01-01", forKey: "data_points_synced_date")

        let state = AppState()
        #expect(state.dataPointsSyncedToday == 0)
    }

    @Test("dataPointsSyncedToday persists for same day")
    func counterPersistsSameDay() {
        cleanDefaults()
        let state = AppState()

        state.dataPointsSyncedToday = 42

        // Reading back should return 42 (same day)
        let state2 = AppState()
        #expect(state2.dataPointsSyncedToday == 42)
    }

    // MARK: recordSyncResult

    @Test("recordSyncResult updates lastSyncTime on success")
    func recordSyncResultUpdatesTime() {
        cleanDefaults()
        let state = AppState()

        let result = SyncResult(
            dataPointCount: 10,
            successfulDestinations: 1,
            failedDestinations: 0,
            duration: 1.5,
            errors: []
        )
        state.recordSyncResult(result)

        #expect(state.lastSyncTime != nil)
        #expect(state.totalSyncsCompleted == 1)
        #expect(state.dataPointsSyncedToday == 10)
    }

    @Test("recordSyncResult does not update lastSyncTime on failure")
    func recordSyncResultFailureNoUpdate() {
        cleanDefaults()
        let state = AppState()

        let result = SyncResult(
            dataPointCount: 0,
            successfulDestinations: 0,
            failedDestinations: 1,
            duration: 0.5,
            errors: [SyncDestinationError(destinationName: "HA", errorDescription: "timeout")]
        )
        state.recordSyncResult(result)

        #expect(state.lastSyncTime == nil)
        #expect(state.totalSyncsCompleted == 0)
    }

    @Test("recordSyncResult updates lastSyncTime when at least one destination succeeds")
    func recordSyncResultPartialSuccessUpdatesTime() {
        cleanDefaults()
        let state = AppState()

        let result = SyncResult(
            dataPointCount: 12,
            successfulDestinations: 1,
            failedDestinations: 1,
            duration: 1.2,
            errors: [SyncDestinationError(destinationName: "Home Assistant", errorDescription: "Timeout")]
        )
        state.recordSyncResult(result)

        #expect(state.lastSyncTime != nil)
        #expect(state.totalSyncsCompleted == 1)
        #expect(state.lastError == "Home Assistant: Timeout")
    }

    // MARK: Onboarding

    @Test("Onboarding flag persists")
    func onboardingFlagPersists() {
        cleanDefaults()
        let state = AppState()

        #expect(!state.hasSeenOnboarding)

        state.hasSeenOnboarding = true

        let state2 = AppState()
        #expect(state2.hasSeenOnboarding)
    }

    // MARK: isSyncOverdue

    @Test("isSyncOverdue returns false when no next sync is scheduled")
    func notOverdueWhenNoSchedule() {
        cleanDefaults()
        let state = AppState()
        #expect(!state.isSyncOverdue)
    }

    @Test("isSyncOverdue returns true when next sync is far in the past")
    func overdueWhenPast() {
        cleanDefaults()
        // Set next scheduled sync to 2 hours ago
        let twoHoursAgo = Date.now.addingTimeInterval(-7200)
        UserDefaults.standard.set(twoHoursAgo.timeIntervalSince1970, forKey: "next_scheduled_sync_time")

        let state = AppState()
        #expect(state.isSyncOverdue)
    }
}
