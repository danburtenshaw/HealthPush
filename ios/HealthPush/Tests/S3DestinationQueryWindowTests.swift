import Foundation
import Testing
@testable import HealthPush

// MARK: - S3DestinationQueryWindowTests

/// Unit-level tests for how ``S3Destination`` chooses its query windows.
///
/// These exercise the pure windowing logic without needing a MinIO instance.
struct S3DestinationQueryWindowTests {
    @Test("Full sync cumulative window spans the user-selected Sync From date")
    func cumulativeWindowHonoursFullSync() throws {
        // Regression: before this test, changing "Sync From" flipped
        // `needsFullSync = true` on the config but cumulative metrics (steps,
        // distance, exercise minutes, etc.) still fell back to a 3-day
        // rolling window in SyncEngine, so only discrete metrics backfilled.
        let destination = try makeDestination(startOption: .last90Days)
        let now = Date.now

        let window = try #require(destination.cumulativeQueryWindow(
            lastSyncedAt: nil,
            needsFullSync: true,
            now: now
        ))

        let daysBack = Calendar.current.dateComponents([.day], from: window.start, to: now).day ?? 0
        #expect(daysBack >= 89, "Expected the cumulative window to reach back ~90 days on full sync, got \(daysBack)")
        #expect(window.end == now)
    }

    @Test("Incremental cumulative window falls through to SyncEngine default")
    func cumulativeWindowIsNilWhenNotFullSync() throws {
        // When not doing a full sync, S3 returns nil so SyncEngine can apply
        // its own short rolling window. This keeps the late-arriving-Watch-data
        // behaviour unchanged.
        let destination = try makeDestination(startOption: .lastYear)

        let window = destination.cumulativeQueryWindow(
            lastSyncedAt: Date.now,
            needsFullSync: false,
            now: .now
        )

        #expect(window == nil)
    }

    @Test("Discrete full-sync window also spans the Sync From date")
    func discreteWindowHonoursFullSync() throws {
        // Paired assertion to keep discrete and cumulative behaviour aligned.
        let destination = try makeDestination(startOption: .last30Days)
        let now = Date.now

        let window = destination.queryWindow(lastSyncedAt: nil, needsFullSync: true, now: now)
        let daysBack = Calendar.current.dateComponents([.day], from: window.start, to: now).day ?? 0
        #expect(daysBack >= 29, "Expected the discrete window to reach back ~30 days on full sync, got \(daysBack)")
    }

    // MARK: Helpers

    private func makeDestination(startOption: SyncStartDateOption) throws -> S3Destination {
        let config = DestinationConfig(
            name: "Test S3",
            destinationType: .s3,
            typeConfig: .s3(S3TypeConfig(
                bucket: "test-bucket",
                region: "us-east-1",
                endpoint: "",
                pathPrefix: "",
                exportFormatRaw: ExportFormat.ndjson.rawValue,
                syncStartDateOptionRaw: startOption.rawValue,
                syncStartDateCustom: nil
            )),
            enabledMetrics: [.steps, .heartRate]
        )
        defer { try? config.deleteAllCredentials() }
        try config.setCredential("AKIAIOSFODNN7EXAMPLE", for: CredentialField.accessKeyID)
        try config.setCredential("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", for: CredentialField.secretAccessKey)
        return try S3Destination(config: config)
    }
}
