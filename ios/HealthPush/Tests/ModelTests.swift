import Testing
import Foundation
import SwiftData
@testable import HealthPush

// MARK: - SyncRecordTests

@Suite("SyncRecord")
struct SyncRecordTests {

    @Test("Creates a sync record with default values")
    func defaultInit() {
        let record = SyncRecord(
            destinationName: "Home Assistant",
            destinationID: UUID()
        )

        #expect(record.destinationName == "Home Assistant")
        #expect(record.status == .inProgress)
        #expect(record.dataPointCount == 0)
        #expect(record.duration == 0)
        #expect(record.errorMessage == nil)
        #expect(!record.isBackgroundSync)
    }

    @Test("Creates a sync record with custom values")
    func customInit() {
        let destID = UUID()
        let record = SyncRecord(
            destinationName: "Test HA",
            destinationID: destID,
            duration: 3.5,
            dataPointCount: 42,
            status: .success,
            isBackgroundSync: true
        )

        #expect(record.destinationName == "Test HA")
        #expect(record.destinationID == destID)
        #expect(record.duration == 3.5)
        #expect(record.dataPointCount == 42)
        #expect(record.status == .success)
        #expect(record.isBackgroundSync)
    }

    @Test("Status getter/setter works correctly")
    func statusProperty() {
        let record = SyncRecord(
            destinationName: "Test",
            destinationID: UUID()
        )

        record.status = .success
        #expect(record.status == .success)
        #expect(record.statusRaw == "success")

        record.status = .failure
        #expect(record.status == .failure)
        #expect(record.statusRaw == "failure")

        record.status = .partialFailure
        #expect(record.status == .partialFailure)
        #expect(record.statusRaw == "partialFailure")
    }
}

// MARK: - DestinationConfigTests

@Suite("DestinationConfig")
struct DestinationConfigTests {

    @Test("Creates a destination config with default values")
    func defaultInit() {
        let config = DestinationConfig()

        #expect(config.name == "Home Assistant")
        #expect(config.destinationType == .homeAssistant)
        #expect(config.isEnabled)
        #expect(config.baseURL.isEmpty)
        #expect(config.apiToken.isEmpty)
        #expect(config.enabledMetrics == Set(HealthMetricType.allCases))
    }

    @Test("Creates a destination config with custom values")
    func customInit() {
        let metrics: Set<HealthMetricType> = [.steps, .heartRate]
        let config = DestinationConfig(
            name: "My HA",
            destinationType: .homeAssistant,
            baseURL: "http://ha.local:8123",
            apiToken: "abc123",
            enabledMetrics: metrics
        )

        #expect(config.name == "My HA")
        #expect(config.baseURL == "http://ha.local:8123")
        #expect(config.apiToken == "abc123")
        #expect(config.enabledMetrics == metrics)
    }

    @Test("Enabled metrics round-trip through raw values")
    func metricsRoundTrip() {
        let config = DestinationConfig()
        let testMetrics: Set<HealthMetricType> = [.steps, .heartRate, .sleepAnalysis]
        config.enabledMetrics = testMetrics
        #expect(config.enabledMetrics == testMetrics)
    }

    @Test("Destination type round-trip through raw value")
    func typeRoundTrip() {
        let config = DestinationConfig()
        config.destinationType = .homeAssistant
        #expect(config.destinationType == .homeAssistant)
        #expect(config.typeRaw == "Home Assistant")
    }

    @Test("Credentials migrate to Keychain-backed storage")
    func keychainMigration() throws {
        let config = DestinationConfig(
            name: "Secure Destination",
            destinationType: .s3,
            baseURL: "healthpush-test",
            apiToken: "AKIA_TEST",
            enabledMetrics: [.steps],
            s3Region: "eu-west-2",
            s3SecretAccessKey: "SECRET_TEST",
            s3Endpoint: "https://s3.example.com"
        )

        defer {
            try? config.deleteStoredSecrets()
        }

        try config.secureStoredSecretsIfNeeded()

        #expect(config.apiToken.isEmpty)
        #expect(config.s3SecretAccessKey.isEmpty)
        #expect((try? config.hasStoredAPIToken) == true)
        #expect((try? config.hasStoredS3SecretAccessKey) == true)
        #expect(try config.resolvedAPIToken == "AKIA_TEST")
        #expect(try config.resolvedS3SecretAccessKey == "SECRET_TEST")
        #expect(config.s3Endpoint == "https://s3.example.com")
    }

    @Test("Stored API token can be removed independently")
    func deleteStoredAPIToken() throws {
        let config = DestinationConfig(
            name: "Secure Destination",
            destinationType: .homeAssistant,
            baseURL: "https://example.com",
            apiToken: "secret"
        )

        try config.secureStoredSecretsIfNeeded()
        try config.deleteStoredAPIToken()

        #expect(config.apiToken.isEmpty)
        #expect(config.apiTokenKeychainKey == nil)
        #expect((try? config.hasStoredAPIToken) == false)
    }
}

// MARK: - SyncStatusTests

@Suite("SyncStatus")
struct SyncStatusTests {

    @Test("All cases have valid raw values")
    func rawValues() {
        #expect(SyncStatus.success.rawValue == "success")
        #expect(SyncStatus.partialFailure.rawValue == "partialFailure")
        #expect(SyncStatus.failure.rawValue == "failure")
        #expect(SyncStatus.inProgress.rawValue == "inProgress")
    }

    @Test("Codable round-trip works")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let statuses: [SyncStatus] = [.success, .partialFailure, .failure, .inProgress]
        for status in statuses {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(SyncStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - DestinationTypeTests

@Suite("DestinationType")
struct DestinationTypeTests {

    @Test("Home Assistant type properties")
    func homeAssistant() {
        let type = DestinationType.homeAssistant
        #expect(type.rawValue == "Home Assistant")
        #expect(type.symbolName == "house.fill")
    }

    @Test("All cases have symbol names")
    func symbolNames() {
        for type in DestinationType.allCases {
            #expect(!type.symbolName.isEmpty)
            #expect(!type.displayName.isEmpty)
        }
    }
}
