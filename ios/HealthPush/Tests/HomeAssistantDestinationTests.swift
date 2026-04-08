import Foundation
import HealthKit
import Testing
@testable import HealthPush

// MARK: - HomeAssistantDestinationTests

struct HomeAssistantDestinationTests {
    // MARK: Helpers

    private func makeConfig(
        baseURL: String = "http://ha.local:8123/api/webhook/healthpush_abc123",
        apiToken: String = "test_secret",
        enabledMetrics: Set<HealthMetricType> = [.steps, .heartRate]
    ) -> DestinationConfig {
        DestinationConfig(
            name: "Test HA",
            destinationType: .homeAssistant,
            baseURL: baseURL,
            apiToken: apiToken,
            enabledMetrics: enabledMetrics
        )
    }

    private func makeDataPoint(
        metricType: HealthMetricType = .steps,
        value: Double = 1234
    ) -> HealthDataPoint {
        HealthDataPoint(
            metricType: metricType,
            value: value,
            unit: metricType.unitString,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            endTimestamp: Date(timeIntervalSince1970: 1_700_003_600),
            sourceName: "Test Device"
        )
    }

    // MARK: Initialization

    @Test("Creates destination from config")
    func initialization() throws {
        let config = makeConfig()
        let destination = try HomeAssistantDestination(config: config)

        #expect(destination.id == config.id)
        #expect(destination.name == "Test HA")
        #expect(destination.isEnabled)
    }

    // MARK: Validation

    @Test("Sync throws with empty URL")
    func emptyURLThrows() async {
        let config = makeConfig(baseURL: "")

        do {
            let destination = try HomeAssistantDestination(config: config)
            try await destination.sync(data: [makeDataPoint()])
            #expect(Bool(false), "Should have thrown")
        } catch let error as HomeAssistantError {
            if case .invalidConfiguration = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test("Sync succeeds with empty secret (no auth)")
    func emptySecretDoesNotThrow() async {
        // An empty webhook secret is valid — it just means no X-Webhook-Secret header
        let config = makeConfig(apiToken: "")

        // This will fail with a connection error (no real server), not a config error
        do {
            let destination = try HomeAssistantDestination(config: config)
            try await destination.sync(data: [makeDataPoint()])
            // If somehow it succeeds, that is fine
        } catch let error as HomeAssistantError {
            if case .invalidConfiguration = error {
                #expect(Bool(false), "Empty secret should not cause invalidConfiguration")
            }
            // syncFailed or connectionFailed are expected without a real server
        } catch {
            // Network errors are expected in tests without a real server
        }
    }

    @Test("Test connection throws with empty URL")
    func connectionEmptyURL() async {
        let config = makeConfig(baseURL: "")

        do {
            let destination = try HomeAssistantDestination(config: config)
            _ = try await destination.testConnection()
            #expect(Bool(false), "Should have thrown")
        } catch let error as HomeAssistantError {
            if case .invalidConfiguration = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    // MARK: Error Types

    @Test("HomeAssistantError has localized descriptions")
    func errorDescriptions() throws {
        let errors: [HomeAssistantError] = [
            .invalidConfiguration("test"),
            .connectionFailed("test"),
            .authenticationFailed,
            .syncFailed("test")
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(try !(#require(error.errorDescription?.isEmpty)))
        }
    }

    // MARK: Protocol Conformance

    @Test("Conforms to SyncDestination")
    func protocolConformance() throws {
        let config = makeConfig()
        let destination = try HomeAssistantDestination(config: config)

        // Verify Identifiable
        #expect(destination.id == config.id)

        // Verify required properties
        #expect(!destination.name.isEmpty)
        #expect(destination.isEnabled)
    }

    @Test("Sleep payload merges asleep intervals and ignores in-bed samples")
    func sleepPayloadAggregatesSleep() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sleepPoints = [
            HealthDataPoint(
                metricType: .sleepAnalysis,
                value: 1.5,
                unit: "hr",
                timestamp: start,
                endTimestamp: start.addingTimeInterval(90 * 60),
                sourceName: "Apple Watch",
                categoryValue: HKCategoryValueSleepAnalysis.asleepCore.rawValue
            ),
            HealthDataPoint(
                metricType: .sleepAnalysis,
                value: 1.5,
                unit: "hr",
                timestamp: start.addingTimeInterval(60 * 60),
                endTimestamp: start.addingTimeInterval(150 * 60),
                sourceName: "Apple Watch",
                categoryValue: HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ),
            HealthDataPoint(
                metricType: .sleepAnalysis,
                value: 6.5,
                unit: "hr",
                timestamp: start.addingTimeInterval(150 * 60),
                endTimestamp: start.addingTimeInterval(540 * 60),
                sourceName: "Apple Watch",
                categoryValue: HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            ),
            HealthDataPoint(
                metricType: .sleepAnalysis,
                value: 9.5,
                unit: "hr",
                timestamp: start.addingTimeInterval(-30 * 60),
                endTimestamp: start.addingTimeInterval(540 * 60),
                sourceName: "Apple Watch",
                categoryValue: HKCategoryValueSleepAnalysis.inBed.rawValue
            )
        ]

        let payload = HomeAssistantDestination.sleepPayload(
            from: sleepPoints,
            formatter: formatter
        )

        #expect(payload != nil)
        #expect(payload?["type"] as? String == "sleep")
        #expect(payload?["value"] as? Double == 9.0)
        #expect(payload?["start_date"] as? String == formatter.string(from: start))
        #expect(
            payload?["end_date"] as? String
                == formatter.string(from: start.addingTimeInterval(540 * 60))
        )
    }
}
