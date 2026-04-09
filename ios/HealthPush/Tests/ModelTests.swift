import Foundation
import SwiftData
import Testing
@testable import HealthPush

// MARK: - SyncRecordTests

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

struct DestinationConfigTests {
    @Test("Creates a Home Assistant destination config with default values")
    func defaultInit() {
        let config = DestinationConfig(
            typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: ""))
        )

        #expect(config.name == "Home Assistant")
        #expect(config.destinationType == .homeAssistant)
        #expect(config.isEnabled)
        #expect(config.enabledMetrics == Set(HealthMetricType.allCases))
        #expect(config.credentialKeys.isEmpty)
    }

    @Test("Creates a destination config with custom values")
    func customInit() {
        let metrics: Set<HealthMetricType> = [.steps, .heartRate]
        let config = DestinationConfig(
            name: "My HA",
            destinationType: .homeAssistant,
            typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: "http://ha.local:8123")),
            enabledMetrics: metrics
        )

        #expect(config.name == "My HA")
        let haConfig = try? config.homeAssistantConfig
        #expect(haConfig?.webhookURL == "http://ha.local:8123")
        #expect(config.enabledMetrics == metrics)
    }

    @Test("Enabled metrics round-trip through raw values")
    func metricsRoundTrip() {
        let config = DestinationConfig(
            typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: ""))
        )
        let testMetrics: Set<HealthMetricType> = [.steps, .heartRate, .sleepAnalysis]
        config.enabledMetrics = testMetrics
        #expect(config.enabledMetrics == testMetrics)
    }

    @Test("Destination type round-trip through raw value")
    func typeRoundTrip() {
        let config = DestinationConfig(
            typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: ""))
        )
        config.destinationType = .homeAssistant
        #expect(config.destinationType == .homeAssistant)
        #expect(config.typeRaw == "Home Assistant")
    }

    @Test("Credentials stored via setCredential and retrieved via credential(for:)")
    func keychainCredentials() throws {
        let config = DestinationConfig(
            name: "Secure Destination",
            destinationType: .s3,
            typeConfig: .s3(S3TypeConfig(
                bucket: "healthpush-test",
                region: "eu-west-2",
                endpoint: "https://s3.example.com",
                pathPrefix: "",
                exportFormatRaw: "json",
                syncStartDateOptionRaw: "last7Days",
                syncStartDateCustom: nil
            )),
            enabledMetrics: [.steps]
        )

        defer {
            try? config.deleteAllCredentials()
        }

        try config.setCredential("AKIAIOSFODNN7EXAMPLE", for: CredentialField.accessKeyID)
        try config.setCredential("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", for: CredentialField.secretAccessKey)

        #expect(config.credentialKeys[CredentialField.accessKeyID] != nil)
        #expect(config.credentialKeys[CredentialField.secretAccessKey] != nil)
        #expect(try config.credential(for: CredentialField.accessKeyID) == "AKIAIOSFODNN7EXAMPLE")
        #expect(try config.credential(for: CredentialField.secretAccessKey) == "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")

        let s3Config = try config.s3Config
        #expect(s3Config.endpoint == "https://s3.example.com")
    }

    @Test("Stored credential can be removed independently")
    func deleteStoredCredential() throws {
        let config = DestinationConfig(
            name: "Secure Destination",
            destinationType: .homeAssistant,
            typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: "https://example.com"))
        )

        try config.setCredential("secret", for: CredentialField.webhookSecret)
        #expect(config.credentialKeys[CredentialField.webhookSecret] != nil)

        try config.deleteCredential(for: CredentialField.webhookSecret)
        #expect(config.credentialKeys[CredentialField.webhookSecret] == nil)
        #expect(try config.credential(for: CredentialField.webhookSecret) == "")
    }

    @Test("TypeSpecificConfig round-trips through JSON encoding")
    func typeConfigRoundTrip() throws {
        let haConfig = TypeSpecificConfig.homeAssistant(
            HomeAssistantTypeConfig(webhookURL: "http://ha.local:8123")
        )
        let encoded = try JSONEncoder().encode(haConfig)
        let decoded = try JSONDecoder().decode(TypeSpecificConfig.self, from: encoded)
        #expect(decoded == haConfig)

        let s3Config = TypeSpecificConfig.s3(S3TypeConfig(
            bucket: "test-bucket",
            region: "us-west-2",
            endpoint: "",
            pathPrefix: "health",
            exportFormatRaw: "csv",
            syncStartDateOptionRaw: "last30Days",
            syncStartDateCustom: nil
        ))
        let s3Encoded = try JSONEncoder().encode(s3Config)
        let s3Decoded = try JSONDecoder().decode(TypeSpecificConfig.self, from: s3Encoded)
        #expect(s3Decoded == s3Config)
    }
}

// MARK: - SyncStatusTests

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
