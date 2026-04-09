import Foundation
import SwiftData
import Testing
@testable import HealthPush

// MARK: - SyncEngineTests

@MainActor
@Suite("SyncEngine orchestration", .serialized)
struct SyncEngineTests {
    // MARK: Helpers

    /// Creates an in-memory SwiftData container suitable for testing.
    private func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([DestinationConfig.self, SyncRecord.self])
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
        fakeReader.queryDataResult = HealthDataQueryResult(
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
        fakeReader.queryDataResult = HealthDataQueryResult(
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
        fakeReader.queryDataResult = HealthDataQueryResult(
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

    @Test("resetAnchors delegates to reader")
    func resetAnchorsDelegatesToReader() async {
        let fakeReader = FakeHealthKitReader()
        let engine = SyncEngine(healthKitReader: fakeReader)

        await engine.resetAnchors()
        #expect(fakeReader.resetAnchorsCallCount == 1)
    }
}
