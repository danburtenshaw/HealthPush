import Foundation
import SwiftData

// MARK: - DestinationType

/// The kind of sync destination.
enum DestinationType: String, Codable, CaseIterable, Identifiable {
    case homeAssistant = "Home Assistant"
    case s3 = "Amazon S3"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .homeAssistant: "Home Assistant"
        case .s3: "S3-Compatible Storage"
        }
    }

    var symbolName: String {
        switch self {
        case .homeAssistant: "house.fill"
        case .s3: "cloud.fill"
        }
    }
}

// MARK: - DestinationConfigError

enum DestinationConfigError: LocalizedError {
    case typeMismatch(expected: DestinationType, actual: DestinationType)
    case corruptTypeConfig

    var errorDescription: String? {
        switch self {
        case let .typeMismatch(expected, actual):
            "Expected \(expected.displayName) config but found \(actual.displayName)."
        case .corruptTypeConfig:
            "Destination configuration data is corrupt."
        }
    }
}

// MARK: - DestinationConfig

/// Persistent configuration for a sync destination, stored via SwiftData.
///
/// Each configured destination (e.g., a Home Assistant instance) gets
/// one of these records. Secrets are stored in Keychain; only reference
/// keys are persisted here via `credentialKeys`.
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

    /// JSON-encoded ``TypeSpecificConfig`` blob.
    var typeConfigData: Data

    /// Maps credential field names to their Keychain keys.
    /// e.g. `["webhookSecret": "destination.<uuid>.webhookSecret"]`
    var credentialKeys: [String: String]

    /// The raw values of the enabled health metric types.
    var enabledMetricRawValues: [String]

    /// When this configuration was created.
    var createdAt: Date

    /// When this configuration was last modified.
    var modifiedAt: Date

    /// When this destination was last successfully synced.
    var lastSyncedAt: Date?

    /// Raw value of the sync frequency for this destination (e.g. "1hr").
    var syncFrequencyRaw = "1hr"

    /// Whether this destination needs a full (non-incremental) sync.
    /// True on creation and when sync start date changes.
    /// Set to false after a successful full sync.
    var needsFullSync = true

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

    /// Decoded type-specific configuration.
    var typeConfig: TypeSpecificConfig {
        get throws {
            try JSONDecoder().decode(TypeSpecificConfig.self, from: typeConfigData)
        }
    }

    /// Sets the type-specific configuration by encoding it to JSON.
    func setTypeConfig(_ config: TypeSpecificConfig) throws {
        typeConfigData = try JSONEncoder().encode(config)
    }

    /// Returns the Home Assistant-specific config, or throws if this isn't an HA destination.
    var homeAssistantConfig: HomeAssistantTypeConfig {
        get throws {
            guard destinationType == .homeAssistant else {
                throw DestinationConfigError.typeMismatch(expected: .homeAssistant, actual: destinationType)
            }
            let config = try typeConfig
            guard case let .homeAssistant(haConfig) = config else {
                throw DestinationConfigError.corruptTypeConfig
            }
            return haConfig
        }
    }

    /// Returns the S3-specific config, or throws if this isn't an S3 destination.
    var s3Config: S3TypeConfig {
        get throws {
            guard destinationType == .s3 else {
                throw DestinationConfigError.typeMismatch(expected: .s3, actual: destinationType)
            }
            let config = try typeConfig
            guard case let .s3(s3Config) = config else {
                throw DestinationConfigError.corruptTypeConfig
            }
            return s3Config
        }
    }

    // MARK: Initialization

    init(
        name: String = "Home Assistant",
        destinationType: DestinationType = .homeAssistant,
        typeConfig: TypeSpecificConfig,
        enabledMetrics: Set<HealthMetricType> = Set(HealthMetricType.allCases)
    ) {
        id = UUID()
        self.name = name
        typeRaw = destinationType.rawValue
        isEnabled = true
        // Force-unwrap is safe: TypeSpecificConfig is a known enum with Codable conformance.
        // swiftlint:disable:next force_try
        typeConfigData = try! JSONEncoder().encode(typeConfig)
        credentialKeys = [:]
        enabledMetricRawValues = enabledMetrics.map(\.rawValue)
        createdAt = .now
        modifiedAt = .now
    }

    // MARK: Credential Management

    /// Loads a credential from the Keychain by its field name.
    func credential(for field: String) throws -> String {
        guard let keychainKey = credentialKeys[field] else {
            return ""
        }
        return try KeychainService.load(keychainKey) ?? ""
    }

    /// Stores a credential in the Keychain and records its reference key.
    func setCredential(_ value: String, for field: String) throws {
        let keychainKey = credentialKeys[field]
            ?? KeychainService.destinationSecretKey(destinationID: id, field: field)
        try KeychainService.save(value, for: keychainKey)
        credentialKeys[field] = keychainKey
    }

    /// Deletes a single credential from the Keychain and removes its reference.
    func deleteCredential(for field: String) throws {
        guard let keychainKey = credentialKeys[field] else { return }
        try KeychainService.delete(keychainKey)
        credentialKeys.removeValue(forKey: field)
    }

    /// Deletes all credentials from the Keychain and clears all references.
    func deleteAllCredentials() throws {
        for (_, keychainKey) in credentialKeys {
            try KeychainService.delete(keychainKey)
        }
        credentialKeys.removeAll()
    }
}
