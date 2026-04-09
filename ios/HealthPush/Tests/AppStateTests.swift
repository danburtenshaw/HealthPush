import Foundation
import Testing
@testable import HealthPush

// MARK: - AppStateTests

@MainActor
struct AppStateTests {
    // MARK: Setup

    /// Creates an isolated `UserDefaults` suite and an `AppState` backed by it.
    /// The suite is automatically removed when the test completes.
    private func makeIsolatedState() -> (AppState, UserDefaults) {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let state = AppState(defaults: defaults)
        return (state, defaults)
    }

    // MARK: lastSyncTime

    @Test("refreshFromUserDefaults loads lastSyncTime from UserDefaults")
    func refreshLoadsLastSyncTime() throws {
        let (state, defaults) = makeIsolatedState()

        let now = Date.now
        defaults.set(now.timeIntervalSince1970, forKey: "last_sync_time")
        state.refreshFromUserDefaults()

        #expect(state.lastSyncTime != nil)
        #expect(try abs(#require(state.lastSyncTime?.timeIntervalSince(now))) < 1)
    }

    @Test("refreshFromUserDefaults sets nil when no sync has occurred")
    func refreshNilWhenNoSync() {
        let (state, _) = makeIsolatedState()

        state.refreshFromUserDefaults()

        #expect(state.lastSyncTime == nil)
    }

    // MARK: dataPointsSyncedToday

    @Test("dataPointsSyncedToday resets when date changes")
    func counterResetsAtMidnight() {
        let (_, defaults) = makeIsolatedState()
        // Set counter with yesterday's date
        defaults.set(100, forKey: "data_points_synced_today")
        defaults.set("1999-01-01", forKey: "data_points_synced_date")

        let state = AppState(defaults: defaults)
        #expect(state.dataPointsSyncedToday == 0)
    }

    @Test("dataPointsSyncedToday persists for same day")
    func counterPersistsSameDay() {
        let (state, defaults) = makeIsolatedState()

        state.dataPointsSyncedToday = 42

        // Reading back from the same defaults should return 42
        let state2 = AppState(defaults: defaults)
        #expect(state2.dataPointsSyncedToday == 42)
    }

    // MARK: recordSyncResult

    @Test("recordSyncResult updates lastSyncTime on success")
    func recordSyncResultUpdatesTime() {
        let (state, _) = makeIsolatedState()

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
        let (state, _) = makeIsolatedState()

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
        let (state, _) = makeIsolatedState()

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
        let (state, defaults) = makeIsolatedState()

        #expect(!state.hasSeenOnboarding)

        state.hasSeenOnboarding = true

        let state2 = AppState(defaults: defaults)
        #expect(state2.hasSeenOnboarding)
    }

    // MARK: isSyncOverdue

    @Test("isSyncOverdue returns false when no next sync is scheduled")
    func notOverdueWhenNoSchedule() {
        let (state, _) = makeIsolatedState()
        #expect(!state.isSyncOverdue)
    }

    @Test("isSyncOverdue returns true when next sync is far in the past")
    func overdueWhenPast() {
        let (_, defaults) = makeIsolatedState()
        // Set next scheduled sync to 2 hours ago
        let twoHoursAgo = Date.now.addingTimeInterval(-7200)
        defaults.set(twoHoursAgo.timeIntervalSince1970, forKey: "next_scheduled_sync_time")

        let state = AppState(defaults: defaults)
        #expect(state.isSyncOverdue)
    }

    // MARK: Test Isolation

    @Test("Tests using different defaults instances do not interfere")
    func testIsolation() {
        let (state1, _) = makeIsolatedState()
        let (state2, _) = makeIsolatedState()

        state1.totalSyncsCompleted = 99
        state1.hasSeenOnboarding = true

        #expect(state2.totalSyncsCompleted == 0)
        #expect(!state2.hasSeenOnboarding)
    }

    // MARK: syncFrequency

    @Test("syncFrequency defaults to one hour")
    func syncFrequencyDefault() {
        let (state, _) = makeIsolatedState()
        #expect(state.syncFrequency == .oneHour)
    }

    @Test("syncFrequency round-trips through defaults")
    func syncFrequencyRoundTrip() {
        let (state, defaults) = makeIsolatedState()
        state.syncFrequency = .sixHours

        let state2 = AppState(defaults: defaults)
        #expect(state2.syncFrequency == .sixHours)
    }

    // MARK: resetToDefaults

    @Test("resetToDefaults clears all state")
    func resetClearsAll() {
        let (state, _) = makeIsolatedState()

        state.hasSeenOnboarding = true
        state.recordSyncResult(SyncResult(
            dataPointCount: 5,
            successfulDestinations: 1,
            failedDestinations: 0,
            duration: 1.0,
            errors: []
        ))

        state.resetToDefaults()

        #expect(!state.hasSeenOnboarding)
        #expect(state.lastSyncTime == nil)
        #expect(state.totalSyncsCompleted == 0)
        #expect(!state.isSyncing)
    }
}
