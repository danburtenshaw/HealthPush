import Foundation
import SwiftData

// MARK: - DestinationType

/// The kind of sync destination.
enum DestinationType: String, Codable, Sendable, CaseIterable, Identifiable {
    case homeAssistant = "Home Assistant"
    case s3 = "Amazon S3"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .homeAssistant: return "house.fill"
        case .s3: return "cloud.fill"
        }
    }
}

// MARK: - DestinationConfig

/// Persistent configuration for a sync destination, stored via SwiftData.
///
/// Each configured destination (e.g., a Home Assistant instance) gets
/// one of these records.
@Model
final class DestinationConfig {

    /// Unique identifier for this destination configuration.
    var id: UUID

    /// Human-readable name (e.g., "My Home Assistant").
    var name: String

    /// The destination type.
    var typeRaw: String

    /// Whether this destination is enabled for syncing.
    var isEnabled: Bool

    /// The base URL for the destination (e.g., Home Assistant URL).
    var baseURL: String

    /// Authentication token or API key.
    var apiToken: String

    /// Keychain entry name for the destination API token.
    var apiTokenKeychainKey: String?

    /// The raw values of the enabled health metric types.
    var enabledMetricRawValues: [String]

    /// When this configuration was created.
    var createdAt: Date

    /// When this configuration was last modified.
    var modifiedAt: Date

    /// When this destination was last successfully synced.
    var lastSyncedAt: Date?

    // MARK: S3-Specific Fields

    /// AWS region for S3 destinations (e.g. "us-east-1").
    var s3Region: String = ""

    /// AWS secret access key for S3 destinations.
    var s3SecretAccessKey: String = ""

    /// Keychain entry name for the S3 secret access key.
    var s3SecretAccessKeyKeychainKey: String?

    /// Path prefix within the S3 bucket (e.g. "health/data").
    var s3PathPrefix: String = ""

    /// Raw value of the export format for S3 destinations.
    var s3ExportFormatRaw: String = "json"

    /// Raw value of the sync frequency for this destination (e.g. "1hr").
    var syncFrequencyRaw: String = "1hr"

    /// Raw value of the sync start date option (e.g. "last7Days").
    var syncStartDateOptionRaw: String = "last7Days"

    /// Custom start date for syncing (only used when syncStartDateOptionRaw == "custom").
    var syncStartDateCustom: Date?

    /// Whether this destination needs a full (non-incremental) sync.
    /// True on creation and when sync start date changes.
    /// Set to false after a successful full sync.
    var needsFullSync: Bool = true

    // MARK: Computed Properties

    var destinationType: DestinationType {
        get { DestinationType(rawValue: typeRaw) ?? .homeAssistant }
        set { typeRaw = newValue.rawValue }
    }

    /// The set of health metrics enabled for this destination.
    var enabledMetrics: Set<HealthMetricType> {
        get {
            Set(enabledMetricRawValues.compactMap { HealthMetricType(rawValue: $0) })
        }
        set {
            enabledMetricRawValues = newValue.map(\.rawValue)
        }
    }

    /// The export format for S3 destinations.
    var exportFormat: ExportFormat {
        get { ExportFormat(rawValue: s3ExportFormatRaw) ?? .json }
        set { s3ExportFormatRaw = newValue.rawValue }
    }

    /// The sync frequency for this destination.
    var syncFrequency: SyncFrequency {
        get { SyncFrequency(rawValue: syncFrequencyRaw) ?? .oneHour }
        set { syncFrequencyRaw = newValue.rawValue }
    }

    /// The next expected sync time for this destination.
    var nextSyncTime: Date? {
        guard let lastSynced = lastSyncedAt else { return nil }
        return lastSynced.addingTimeInterval(syncFrequency.timeInterval)
    }

    /// The sync start date option.
    var syncStartDateOption: SyncStartDateOption {
        get { SyncStartDateOption(rawValue: syncStartDateOptionRaw) ?? .last7Days }
        set { syncStartDateOptionRaw = newValue.rawValue }
    }

    /// The resolved start date for the full sync window.
    var resolvedSyncStartDate: Date {
        syncStartDateOption.resolvedDate(customDate: syncStartDateCustom)
    }

    /// The resolved API token, preferring Keychain-backed storage.
    var resolvedAPIToken: String {
        get throws {
            try apiTokenValue(migratingIfNeeded: true)
        }
    }

    /// The resolved S3 secret access key, preferring Keychain-backed storage.
    var resolvedS3SecretAccessKey: String {
        get throws {
            try s3SecretAccessKeyValue(migratingIfNeeded: true)
        }
    }

    /// Creates a new destination configuration.
    /// - Parameters:
    ///   - name: Display name for the destination.
    ///   - destinationType: The type of destination.
    ///   - baseURL: The URL for the destination API.
    ///   - apiToken: Authentication token.
    ///   - enabledMetrics: Which health metrics to sync.
    init(
        name: String = "Home Assistant",
        destinationType: DestinationType = .homeAssistant,
        baseURL: String = "",
        apiToken: String = "",
        enabledMetrics: Set<HealthMetricType> = Set(HealthMetricType.allCases),
        s3Region: String = "",
        s3SecretAccessKey: String = "",
        s3PathPrefix: String = "",
        s3ExportFormat: ExportFormat = .json
    ) {
        self.id = UUID()
        self.name = name
        self.typeRaw = destinationType.rawValue
        self.isEnabled = true
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.apiTokenKeychainKey = nil
        self.enabledMetricRawValues = enabledMetrics.map(\.rawValue)
        self.createdAt = .now
        self.modifiedAt = .now
        self.s3Region = s3Region
        self.s3SecretAccessKey = s3SecretAccessKey
        self.s3SecretAccessKeyKeychainKey = nil
        self.s3PathPrefix = s3PathPrefix
        self.s3ExportFormatRaw = s3ExportFormat.rawValue
    }

    // MARK: Secret Storage

    func secureStoredSecretsIfNeeded() throws {
        if !apiToken.isEmpty {
            let key = apiTokenKeychainKey
                ?? KeychainService.destinationSecretKey(destinationID: id, field: "api_token")
            try KeychainService.save(apiToken, for: key)
            apiTokenKeychainKey = key
            apiToken = ""
        }

        if !s3SecretAccessKey.isEmpty {
            let key = s3SecretAccessKeyKeychainKey
                ?? KeychainService.destinationSecretKey(destinationID: id, field: "s3_secret_access_key")
            try KeychainService.save(s3SecretAccessKey, for: key)
            s3SecretAccessKeyKeychainKey = key
            s3SecretAccessKey = ""
        }
    }

    func deleteStoredSecrets() throws {
        if let apiTokenKeychainKey {
            try KeychainService.delete(apiTokenKeychainKey)
            self.apiTokenKeychainKey = nil
        }

        if let s3SecretAccessKeyKeychainKey {
            try KeychainService.delete(s3SecretAccessKeyKeychainKey)
            self.s3SecretAccessKeyKeychainKey = nil
        }
    }

    func apiTokenValue(migratingIfNeeded shouldMigrate: Bool) throws -> String {
        if let apiTokenKeychainKey {
            return try KeychainService.load(apiTokenKeychainKey) ?? ""
        }
        if shouldMigrate, !apiToken.isEmpty {
            try secureStoredSecretsIfNeeded()
            return try apiTokenValue(migratingIfNeeded: false)
        }
        return apiToken
    }

    func s3SecretAccessKeyValue(migratingIfNeeded shouldMigrate: Bool) throws -> String {
        if let s3SecretAccessKeyKeychainKey {
            return try KeychainService.load(s3SecretAccessKeyKeychainKey) ?? ""
        }
        if shouldMigrate, !s3SecretAccessKey.isEmpty {
            try secureStoredSecretsIfNeeded()
            return try s3SecretAccessKeyValue(migratingIfNeeded: false)
        }
        return s3SecretAccessKey
    }
}
