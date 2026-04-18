import Foundation
import SwiftData
import Testing
@testable import HealthPush

// MARK: - SyncEngineTests

@MainActor
@Suite(.serialized)
struct SyncEngineTests {
    // MARK: Helpers

    /// Creates an in-memory SwiftData container suitable for testing.
    private func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([DestinationConfig.self, SyncRecord.self, MetricSyncAnchor.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Creates a `NetworkService` backed by `SyncEngineStubProtocol` for fast tests.
    private func makeStubNetworkService() -> NetworkService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyncEngineStubProtocol.self]
        return NetworkService(configuration: config)
    }

    /// Inserts an enabled Home Assistant destination config into the given context.
    @discardableResult
    private func insertHAConfig(
        into context: ModelContext,
        webhookURL: String = "http://ha.local:8123/api/webhook/healthpush_test",
        webhookSecret: String = "test_secret",
        enabledMetrics: Set<HealthMetricType> = [.heartRate]
    ) throws -> DestinationConfig {
        let config = DestinationConfig(
            name: "Test HA",
            destinationType: .homeAssistant,
            typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: webhookURL)),
            enabledMetrics: enabledMetrics
        )
        if !webhookSecret.isEmpty {
            try config.setCredential(webhookSecret, for: CredentialField.webhookSecret)
        }
        context.insert(config)
        try context.save()
        return config
    }

    /// Creates a sample heart rate data point.
    private func makeHeartRatePoint(value: Double = 72.0) -> HealthDataPoint {
        HealthDataPoint(
            metricType: .heartRate,
            value: value,
            unit: "count/min",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_060),
            sourceName: "Test Device"
        )
    }

    // MARK: Tests

    @Test("Happy path: sync with data returns correct counts")
    func happyPathSync() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )

        // Stub the network to return 200 so the sync succeeds without a real server.
        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        let result = await engine.performSync(modelContext: context)

        // Data was queried from the fake reader
        #expect(fakeReader.queryDataCallCount >= 1)
        // Destination should succeed with the stubbed 200 response
        #expect(result.successfulDestinations == 1)
        #expect(result.failedDestinations == 0)
        #expect(result.dataPointCount >= 1)
    }

    @Test("No destinations: returns zero counts gracefully")
    func noDestinationsSync() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)
        // Do not insert any destination configs

        let fakeReader = FakeHealthKitReader()
        let engine = SyncEngine(healthKitReader: fakeReader)

        let result = await engine.performSync(modelContext: context)

        #expect(result.dataPointCount == 0)
        #expect(result.successfulDestinations == 0)
        #expect(result.failedDestinations == 0)
        #expect(result.errors.isEmpty)
        // HealthKit should not be queried when there are no destinations
        #expect(fakeReader.queryDataCallCount == 0)
    }

    @Test("HealthKit unavailable: returns error without crashing")
    func healthKitUnavailableSync() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        // Pass nil reader to simulate HealthKit being unavailable
        let engine = SyncEngine(healthKitReader: nil)

        let result = await engine.performSync(modelContext: context)

        #expect(result.dataPointCount == 0)
        #expect(result.successfulDestinations == 0)
        #expect(result.failedDestinations == 0)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.destinationName == "HealthKit")
    }

    @Test("Disabled destinations are skipped")
    func disabledDestinationsSkipped() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = DestinationConfig(
            name: "Disabled HA",
            destinationType: .homeAssistant,
            typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: "http://ha.local:8123")),
            enabledMetrics: [.heartRate]
        )
        config.isEnabled = false
        context.insert(config)
        try context.save()

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )
        let engine = SyncEngine(healthKitReader: fakeReader)

        let result = await engine.performSync(modelContext: context)

        // Disabled destinations are filtered by the predicate, so no query should happen
        #expect(result.dataPointCount == 0)
        #expect(result.successfulDestinations == 0)
        #expect(result.failedDestinations == 0)
        #expect(fakeReader.queryDataCallCount == 0)
    }

    @Test("Destinations with no enabled metrics are skipped")
    func noEnabledMetricsSkipped() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(
            into: context,
            enabledMetrics: []
        )
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )
        let engine = SyncEngine(healthKitReader: fakeReader)

        let result = await engine.performSync(modelContext: context)

        // The destination exists but has no metrics, so it should be skipped entirely
        #expect(fakeReader.queryDataCallCount == 0)
        #expect(result.dataPointCount == 0)
    }

    @Test("requestHealthKitAuthorization throws when reader is nil")
    func authorizationThrowsWhenUnavailable() async throws {
        let engine = SyncEngine(healthKitReader: nil)

        await #expect(throws: SyncError.self) {
            try await engine.requestHealthKitAuthorization(for: [.heartRate])
        }
    }

    @Test("requestHealthKitAuthorization delegates to reader")
    func authorizationDelegatesToReader() async throws {
        let fakeReader = FakeHealthKitReader()
        let engine = SyncEngine(healthKitReader: fakeReader)

        try await engine.requestHealthKitAuthorization(for: [.heartRate, .steps])
        #expect(fakeReader.requestAuthCallCount == 1)
    }

    @Test("resetAnchors clears stored anchors and forces full re-sync")
    func resetAnchorsClearsStoredAnchors() throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        // Seed an anchor record and mark the destination as already-synced.
        let seededAnchor = MetricSyncAnchor(
            destinationID: config.id,
            metric: .heartRate,
            anchorData: Data([0x01, 0x02, 0x03])
        )
        context.insert(seededAnchor)
        config.lastSyncedAt = .now
        config.needsFullSync = false
        try context.save()

        let engine = SyncEngine(healthKitReader: FakeHealthKitReader())
        engine.resetAnchors(modelContext: context)

        let remaining = try context.fetch(FetchDescriptor<MetricSyncAnchor>())
        #expect(remaining.isEmpty)
        #expect(config.needsFullSync == true)
        #expect(config.lastSyncedAt == nil)
    }

    // MARK: - State persistence tests (the bugs that were found in production)

    @Test("Successful sync sets lastSyncedAt and clears needsFullSync")
    func successfulSyncUpdatesConfigState() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        // Verify initial state
        #expect(config.lastSyncedAt == nil)
        #expect(config.needsFullSync == true)

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )

        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        _ = await engine.performSync(modelContext: context)

        // After successful sync, config state must be updated
        #expect(config.lastSyncedAt != nil)
        #expect(config.needsFullSync == false)
    }

    @Test("Partial success (query issues) still sets lastSyncedAt")
    func partialSuccessUpdatesConfigState() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context, enabledMetrics: [.heartRate, .steps])
        defer { try? config.deleteAllCredentials() }

        // Return data but with query issues for one metric
        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: [HealthMetricQueryIssue(
                metric: .steps,
                errorDescription: "Authorization not determined"
            )]
        )

        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        let result = await engine.performSync(modelContext: context)

        // Partial success: data was delivered, so lastSyncedAt must be set
        #expect(config.lastSyncedAt != nil)
        #expect(config.needsFullSync == false)
        // Still counts as a successful delivery
        #expect(result.successfulDestinations == 1)
        #expect(result.failedDestinations == 0)
    }

    @Test("Network failure does NOT set lastSyncedAt")
    func networkFailureDoesNotUpdateConfigState() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )

        // Return 500 to simulate server error
        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("Server Error".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        let result = await engine.performSync(modelContext: context)

        // Failed sync must NOT update lastSyncedAt
        #expect(config.lastSyncedAt == nil)
        #expect(config.needsFullSync == true)
        #expect(result.failedDestinations == 1)
        #expect(result.successfulDestinations == 0)
    }

    @Test("SyncRecord is created with correct status on success")
    func syncRecordCreatedOnSuccess() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )

        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        _ = await engine.performSync(modelContext: context)

        let records = try context.fetch(FetchDescriptor<SyncRecord>())
        #expect(records.count == 1)
        #expect(records.first?.status == .success)
        #expect(records.first?.destinationName == "Test HA")
        #expect(records.first?.dataPointCount == 1)
    }

    @Test("SyncRecord is created with failure status on network error")
    func syncRecordCreatedOnFailure() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )

        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("fail".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        _ = await engine.performSync(modelContext: context)

        let records = try context.fetch(FetchDescriptor<SyncRecord>())
        #expect(records.count == 1)
        #expect(records.first?.status == .failure)
        #expect(records.first?.failureCategoryRaw != nil)
    }

    @Test("processedDataPointCount tracks total HealthKit points, not just new ones")
    func processedCountDistinctFromNewCount() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [
                makeHeartRatePoint(value: 72),
                makeHeartRatePoint(value: 75),
                makeHeartRatePoint(value: 80)
            ],
            issues: []
        )

        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        let result = await engine.performSync(modelContext: context)

        // HealthKit returned 3 points total
        #expect(result.processedDataPointCount >= 3)
        // HA sends latest-per-metric so newCount may differ, but processed should reflect all queried
        #expect(result.processedDataPointCount >= result.dataPointCount)
    }

    @Test("Background mode skips recently synced destinations")
    func backgroundSkipsRecentlySynced() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        // Simulate a recent sync
        config.lastSyncedAt = .now
        config.needsFullSync = false
        try context.save()

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        // Background sync should skip this destination because it was synced recently
        let result = await engine.performSync(modelContext: context, isBackground: true)

        #expect(result.dataPointCount == 0)
        #expect(result.successfulDestinations == 0)
        // HealthKit should not be queried since the destination was skipped
        #expect(fakeReader.queryDataCallCount == 0)
    }

    @Test("Manual sync does NOT skip recently synced destinations")
    func manualSyncDoesNotSkip() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        // Simulate a recent sync
        config.lastSyncedAt = .now
        config.needsFullSync = false
        try context.save()

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: []
        )

        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        // Manual sync (isBackground: false) should always run
        let result = await engine.performSync(modelContext: context, isBackground: false)

        #expect(fakeReader.queryDataCallCount >= 1)
        #expect(result.successfulDestinations == 1)
    }

    // MARK: - Reliability: defer + anchor persistence

    @Test("Offline: every destination is deferred, none failed, no HK query attempted")
    func offlineDefersAllDestinations() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        // If we reach the reader, the test is wrong — offline gate should bail first.
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()]
        )

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService(),
            networkMonitor: AlwaysOfflineMonitor()
        )

        let result = await engine.performSync(modelContext: context)

        #expect(result.successfulDestinations == 0)
        #expect(result.failedDestinations == 0)
        #expect(result.deferredDestinations == 1)
        #expect(fakeReader.queryDataCallCount == 0)

        // The persisted SyncRecord should be marked deferred, not failed,
        // so the history UI doesn't render it as a red error.
        let records = try context.fetch(FetchDescriptor<SyncRecord>())
        #expect(records.count == 1)
        #expect(records.first?.status == .deferred)
        #expect(records.first?.failureCategory?.deferReason == .offline)
    }

    @Test("Successful sync persists per-(destination, metric) anchors")
    func successfulSyncPersistsAnchors() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context, enabledMetrics: [.heartRate])
        defer { try? config.deleteAllCredentials() }

        let anchorBlob = Data([0xAA, 0xBB, 0xCC])
        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: [],
            newAnchors: [.heartRate: anchorBlob]
        )

        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        _ = await engine.performSync(modelContext: context)

        // Anchor must be stored and tied to this destination + metric.
        let stored = try context.fetch(FetchDescriptor<MetricSyncAnchor>())
        #expect(stored.count == 1)
        #expect(stored.first?.destinationID == config.id)
        #expect(stored.first?.metricRawValue == HealthMetricType.heartRate.rawValue)
        #expect(stored.first?.anchorData == anchorBlob)
    }

    @Test("Failed sync does NOT persist anchors — next sync retries the same window")
    func failedSyncDoesNotPersistAnchors() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: [],
            newAnchors: [.heartRate: Data([0x42])]
        )

        // Server error — destination sync throws, anchor must NOT be saved.
        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("fail".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        _ = await engine.performSync(modelContext: context)

        let stored = try context.fetch(FetchDescriptor<MetricSyncAnchor>())
        #expect(stored.isEmpty)
    }

    @Test("Subsequent sync passes the previously stored anchor back to the reader")
    func subsequentSyncReusesStoredAnchor() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context, enabledMetrics: [.heartRate])
        defer { try? config.deleteAllCredentials() }

        // Mark as already-synced so the engine takes the incremental path
        // (anchor lookup) instead of using the destination's full-sync window.
        config.lastSyncedAt = .now.addingTimeInterval(-3600)
        config.needsFullSync = false
        try context.save()

        let firstAnchor = Data([0x01, 0x02])
        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()],
            issues: [],
            newAnchors: [.heartRate: firstAnchor]
        )

        SyncEngineStubProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://ha.local:8123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        // First run — anchor saved.
        _ = await engine.performSync(modelContext: context)

        // Second run — engine should hand the stored anchor back to the reader.
        // Mark recent-sync window past so the engine doesn't skip the destination.
        config.lastSyncedAt = .now.addingTimeInterval(-3600)
        try context.save()
        _ = await engine.performSync(modelContext: context)

        #expect(fakeReader.lastQueriedAnchors[.heartRate] == firstAnchor)
    }

    @Test("URLError.cancelled is classified as deferred(.outOfTime), not a failure")
    func cancelledRequestIsDeferred() async throws {
        let container = try makeModelContainer()
        let context = ModelContext(container)

        let config = try insertHAConfig(into: context)
        defer { try? config.deleteAllCredentials() }

        let fakeReader = FakeHealthKitReader()
        fakeReader.queryDataResult = HealthAnchoredQueryResult(
            dataPoints: [makeHeartRatePoint()]
        )

        // Throw URLError.cancelled — this is what URLSession raises when
        // BGTask.expirationHandler cancels the parent task mid-flight.
        SyncEngineStubProtocol.requestHandler = { _ in
            throw URLError(.cancelled)
        }

        let engine = SyncEngine(
            healthKitReader: fakeReader,
            networkService: makeStubNetworkService()
        )

        let result = await engine.performSync(modelContext: context)

        #expect(result.failedDestinations == 0)
        #expect(result.deferredDestinations == 1)
        let records = try context.fetch(FetchDescriptor<SyncRecord>())
        #expect(records.first?.status == .deferred)
        #expect(records.first?.failureCategory?.deferReason == .outOfTime)
    }
}

// MARK: - Test helpers

/// `NetworkPathMonitoring` that always reports unreachable. Used to drive
/// the offline-defer path in tests.
private struct AlwaysOfflineMonitor: NetworkPathMonitoring {
    var isReachable: Bool {
        false
    }
}
