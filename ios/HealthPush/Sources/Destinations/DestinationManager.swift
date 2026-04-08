import Foundation
import Observation
import os
import SwiftData

// MARK: - DestinationManagerError

enum DestinationManagerError: LocalizedError {
    case secretStorageFailed(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case let .secretStorageFailed(message):
            "Failed to secure destination credentials: \(message)"
        case let .persistenceFailed(message):
            "Failed to save destination changes: \(message)"
        }
    }
}

// MARK: - DestinationManager

/// Manages the lifecycle of sync destinations.
///
/// This class provides a high-level interface for creating, updating, deleting,
/// and testing destinations. It persists configuration via SwiftData.
@MainActor
@Observable
final class DestinationManager {
    // MARK: Properties

    private let logger = Logger(subsystem: "app.healthpush", category: "DestinationManager")
    private let networkService = NetworkService()

    /// All configured destinations, kept in sync with SwiftData.
    var destinations: [DestinationConfig] = []

    /// Called after any CRUD operation so the app can re-register observer queries
    /// and re-schedule background tasks for the updated set of destinations.
    var onDestinationsChanged: (() -> Void)?

    /// Whether a connection test is in progress.
    var isTesting = false

    /// The result of the last connection test.
    var lastTestResult: TestResult?

    // MARK: Test Result

    enum TestResult {
        case success
        case failure(String)
    }

    // MARK: Loading

    /// Fetches all destination configurations from SwiftData.
    /// - Parameter modelContext: The SwiftData model context.
    func loadDestinations(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DestinationConfig>(
            sortBy: [SortDescriptor(\DestinationConfig.createdAt)]
        )
        do {
            destinations = try modelContext.fetch(descriptor)
            var didMigrateSecrets = false
            for config in destinations {
                do {
                    let hadPlaintextSecrets = !config.apiToken.isEmpty || !config.s3SecretAccessKey.isEmpty
                    try config.secureStoredSecretsIfNeeded()
                    didMigrateSecrets = didMigrateSecrets || hadPlaintextSecrets
                } catch {
                    logger.error("Failed to migrate secrets for \(config.name): \(error.localizedDescription)")
                }
            }
            if didMigrateSecrets {
                try modelContext.save()
            }
        } catch {
            logger.error("Failed to fetch destinations: \(error.localizedDescription)")
            destinations = []
        }
    }

    // MARK: CRUD Operations

    /// Creates a new Home Assistant destination.
    /// - Parameters:
    ///   - name: Display name.
    ///   - baseURL: The Home Assistant base URL.
    ///   - apiToken: Long-lived access token.
    ///   - enabledMetrics: Which metrics to sync.
    ///   - modelContext: The SwiftData model context.
    /// - Returns: The created configuration.
    @discardableResult
    func createHomeAssistantDestination(
        name: String,
        baseURL: String,
        apiToken: String,
        enabledMetrics: Set<HealthMetricType>,
        syncFrequency: SyncFrequency = .oneHour,
        modelContext: ModelContext
    ) throws -> DestinationConfig {
        let config = DestinationConfig(
            name: name,
            destinationType: .homeAssistant,
            baseURL: baseURL,
            apiToken: apiToken,
            enabledMetrics: enabledMetrics
        )
        config.syncFrequency = syncFrequency
        modelContext.insert(config)

        do {
            try config.secureStoredSecretsIfNeeded()
            try modelContext.save()
            loadDestinations(modelContext: modelContext)
            onDestinationsChanged?()
            logger.info("Created destination: \(name)")
        } catch {
            modelContext.delete(config)
            logger.error("Failed to save destination: \(error.localizedDescription)")
            if error is KeychainError {
                throw DestinationManagerError.secretStorageFailed(error.localizedDescription)
            }
            throw DestinationManagerError.persistenceFailed(error.localizedDescription)
        }

        return config
    }

    /// Updates an existing destination configuration.
    /// - Parameters:
    ///   - config: The configuration to update.
    ///   - modelContext: The SwiftData model context.
    func updateDestination(_ config: DestinationConfig, modelContext: ModelContext) throws {
        config.modifiedAt = .now
        do {
            try config.secureStoredSecretsIfNeeded()
            try modelContext.save()
            loadDestinations(modelContext: modelContext)
            onDestinationsChanged?()
            logger.info("Updated destination: \(config.name)")
        } catch {
            logger.error("Failed to update destination: \(error.localizedDescription)")
            if error is KeychainError {
                throw DestinationManagerError.secretStorageFailed(error.localizedDescription)
            }
            throw DestinationManagerError.persistenceFailed(error.localizedDescription)
        }
    }

    /// Deletes a destination configuration.
    /// - Parameters:
    ///   - config: The configuration to delete.
    ///   - modelContext: The SwiftData model context.
    func deleteDestination(_ config: DestinationConfig, modelContext: ModelContext) throws {
        let apiTokenKeychainKey = config.apiTokenKeychainKey
        let s3SecretAccessKeyKeychainKey = config.s3SecretAccessKeyKeychainKey
        let destinationID = config.id

        let descriptor = FetchDescriptor<SyncRecord>(
            predicate: #Predicate<SyncRecord> { record in
                record.destinationID == destinationID
            }
        )
        if let records = try? modelContext.fetch(descriptor) {
            for record in records {
                modelContext.delete(record)
            }
        }

        modelContext.delete(config)
        do {
            try modelContext.save()
            loadDestinations(modelContext: modelContext)
            onDestinationsChanged?()

            if let apiTokenKeychainKey {
                try? KeychainService.delete(apiTokenKeychainKey)
            }
            if let s3SecretAccessKeyKeychainKey {
                try? KeychainService.delete(s3SecretAccessKeyKeychainKey)
            }

            logger.info("Deleted destination and its sync history: \(config.name)")
        } catch {
            logger.error("Failed to delete destination: \(error.localizedDescription)")
            throw DestinationManagerError.persistenceFailed(error.localizedDescription)
        }
    }

    // MARK: S3 Destination

    /// Creates a new S3 destination.
    @discardableResult
    func createS3Destination(
        name: String,
        bucket: String,
        region: String,
        endpoint: String,
        accessKeyID: String,
        secretAccessKey: String,
        pathPrefix: String,
        exportFormat: ExportFormat,
        enabledMetrics: Set<HealthMetricType>,
        syncFrequency: SyncFrequency = .oneHour,
        syncStartDateOption: SyncStartDateOption = .last7Days,
        syncStartDateCustom: Date? = nil,
        modelContext: ModelContext
    ) throws -> DestinationConfig {
        let config = DestinationConfig(
            name: name,
            destinationType: .s3,
            baseURL: bucket,
            apiToken: accessKeyID,
            enabledMetrics: enabledMetrics,
            s3Region: region,
            s3SecretAccessKey: secretAccessKey,
            s3PathPrefix: pathPrefix,
            s3Endpoint: endpoint,
            s3ExportFormat: exportFormat
        )
        config.syncFrequency = syncFrequency
        config.syncStartDateOption = syncStartDateOption
        config.syncStartDateCustom = syncStartDateCustom
        config.needsFullSync = true
        modelContext.insert(config)

        do {
            try config.secureStoredSecretsIfNeeded()
            try modelContext.save()
            loadDestinations(modelContext: modelContext)
            onDestinationsChanged?()
            logger.info("Created S3 destination: \(name)")
        } catch {
            modelContext.delete(config)
            logger.error("Failed to save S3 destination: \(error.localizedDescription)")
            if error is KeychainError {
                throw DestinationManagerError.secretStorageFailed(error.localizedDescription)
            }
            throw DestinationManagerError.persistenceFailed(error.localizedDescription)
        }

        return config
    }

    // MARK: Connection Testing

    /// Tests the connection to a destination.
    /// - Parameter config: The destination configuration to test.
    func testConnection(for config: DestinationConfig) async {
        isTesting = true
        lastTestResult = nil

        do {
            var success = false
            switch config.destinationType {
            case .homeAssistant:
                let destination = try HomeAssistantDestination(
                    config: config,
                    networkService: networkService
                )
                success = try await destination.testConnection()
            case .s3:
                let destination = try S3Destination(config: config)
                success = try await destination.testConnection()
            }
            lastTestResult = success ? .success : .failure("Connection test returned false.")
        } catch {
            lastTestResult = .failure(error.localizedDescription)
        }

        isTesting = false
    }
}
