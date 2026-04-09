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
        } catch {
            logger.error("Failed to fetch destinations: \(error.localizedDescription)")
            destinations = []
        }
    }

    // MARK: CRUD Operations

    /// Creates a new destination with the given configuration.
    @discardableResult
    func createDestination(
        name: String,
        type: DestinationType,
        typeConfig: TypeSpecificConfig,
        credentials: [String: String],
        enabledMetrics: Set<HealthMetricType>,
        syncFrequency: SyncFrequency = .oneHour,
        modelContext: ModelContext
    ) throws -> DestinationConfig {
        let config = DestinationConfig(
            name: name,
            destinationType: type,
            typeConfig: typeConfig,
            enabledMetrics: enabledMetrics
        )
        config.syncFrequency = syncFrequency
        modelContext.insert(config)

        do {
            for (field, value) in credentials where !value.isEmpty {
                try config.setCredential(value, for: field)
            }
            try modelContext.save()
            loadDestinations(modelContext: modelContext)
            onDestinationsChanged?()
            logger.info("Created destination: \(name)")
        } catch {
            // Rollback: clean up any credentials we stored, then remove the model
            try? config.deleteAllCredentials()
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
        let credentialKeysSnapshot = config.credentialKeys
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

            for (_, keychainKey) in credentialKeysSnapshot {
                try? KeychainService.delete(keychainKey)
            }

            logger.info("Deleted destination and its sync history: \(config.name)")
        } catch {
            logger.error("Failed to delete destination: \(error.localizedDescription)")
            throw DestinationManagerError.persistenceFailed(error.localizedDescription)
        }
    }

    // MARK: Data Erasure

    /// Performs a complete erasure of all HealthPush data.
    ///
    /// This method is best-effort: if any step fails it logs the error and
    /// continues with the remaining steps so that as much data as possible is removed.
    ///
    /// Steps performed:
    /// 1. Delete all Keychain entries for every destination.
    /// 2. Delete all ``SyncRecord`` objects from SwiftData.
    /// 3. Delete all ``DestinationConfig`` objects from SwiftData.
    /// 4. Save the model context.
    /// 5. Clear the in-memory destinations array.
    /// 6. Reset ``AppState`` to factory defaults.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData model context.
    ///   - appState: The app state to reset.
    func eraseAll(modelContext: ModelContext, appState: AppState) {
        // 1. Delete all Keychain entries for every destination
        for config in destinations {
            for (_, keychainKey) in config.credentialKeys {
                do {
                    try KeychainService.delete(keychainKey)
                } catch {
                    logger.error("Failed to delete keychain item \(keychainKey): \(error.localizedDescription)")
                }
            }
        }

        // Belt-and-suspenders: sweep the entire service to catch any orphans
        do {
            try KeychainService.deleteAllServiceItems()
        } catch {
            logger.error("Failed to sweep keychain service items: \(error.localizedDescription)")
        }

        // 2. Delete all SyncRecord objects
        do {
            try modelContext.delete(model: SyncRecord.self)
        } catch {
            logger.error("Failed to delete sync records: \(error.localizedDescription)")
        }

        // 3. Delete all DestinationConfig objects
        do {
            try modelContext.delete(model: DestinationConfig.self)
        } catch {
            logger.error("Failed to delete destination configs: \(error.localizedDescription)")
        }

        // 4. Save the context
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save model context after erasure: \(error.localizedDescription)")
        }

        // 5. Clear in-memory destinations
        destinations = []

        // 6. Reset AppState to factory defaults
        appState.resetToDefaults()

        logger.info("Completed full data erasure")
    }

    // MARK: Destination Factory

    /// Creates a ``SyncDestination`` instance from a persisted configuration.
    func makeDestination(for config: DestinationConfig) throws -> any SyncDestination {
        switch config.destinationType {
        case .homeAssistant:
            try HomeAssistantDestination(config: config, networkService: networkService)
        case .s3:
            try S3Destination(config: config)
        }
    }

    // MARK: Connection Testing

    /// Tests the connection to a destination.
    /// - Parameter config: The destination configuration to test.
    func testConnection(for config: DestinationConfig) async {
        isTesting = true
        lastTestResult = nil

        do {
            let destination = try makeDestination(for: config)
            let success = try await destination.testConnection()
            lastTestResult = success ? .success : .failure("Connection test returned false.")
        } catch {
            lastTestResult = .failure(error.localizedDescription)
        }

        isTesting = false
    }
}
