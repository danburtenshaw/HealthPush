import Foundation

// MARK: - CredentialField

enum CredentialField {
    static let webhookSecret = "webhookSecret"
    static let accessKeyID = "accessKeyID"
    static let secretAccessKey = "secretAccessKey"
}

// MARK: - TypeSpecificConfig

/// Destination-specific configuration stored as a JSON blob in DestinationConfig.
enum TypeSpecificConfig: Codable, Equatable, Sendable {
    case homeAssistant(HomeAssistantTypeConfig)
    case s3(S3TypeConfig)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum TypeDiscriminator: String, Codable {
        case homeAssistant = "Home Assistant"
        case s3 = "Amazon S3"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TypeDiscriminator.self, forKey: .type)
        switch type {
        case .homeAssistant:
            self = .homeAssistant(try HomeAssistantTypeConfig(from: decoder))
        case .s3:
            self = .s3(try S3TypeConfig(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .homeAssistant(config):
            try container.encode(TypeDiscriminator.homeAssistant, forKey: .type)
            try config.encode(to: encoder)
        case let .s3(config):
            try container.encode(TypeDiscriminator.s3, forKey: .type)
            try config.encode(to: encoder)
        }
    }
}

// MARK: - HomeAssistantTypeConfig

struct HomeAssistantTypeConfig: Codable, Equatable, Sendable {
    var webhookURL: String
}

// MARK: - S3TypeConfig

struct S3TypeConfig: Codable, Equatable, Sendable {
    var bucket: String
    var region: String
    var endpoint: String
    var pathPrefix: String
    var exportFormatRaw: String
    var syncStartDateOptionRaw: String
    var syncStartDateCustom: Date?

    var exportFormat: ExportFormat {
        get { ExportFormat(rawValue: exportFormatRaw) ?? .json }
        set { exportFormatRaw = newValue.rawValue }
    }

    var syncStartDateOption: SyncStartDateOption {
        get { SyncStartDateOption(rawValue: syncStartDateOptionRaw) ?? .last7Days }
        set { syncStartDateOptionRaw = newValue.rawValue }
    }

    var resolvedSyncStartDate: Date {
        syncStartDateOption.resolvedDate(customDate: syncStartDateCustom)
    }

    // MARK: - Validation

    /// Validates an S3 bucket name per AWS naming rules.
    /// Returns nil if valid, or an error message string if invalid.
    static func validateBucketName(_ name: String) -> String? {
        if name.isEmpty { return "Bucket name is required" }
        if name.count < 3 { return "Bucket name must be at least 3 characters" }
        if name.count > 63 { return "Bucket name cannot exceed 63 characters" }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-."))
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Only lowercase letters, numbers, hyphens, and dots allowed"
        }
        if name.hasPrefix("-") || name.hasPrefix(".") {
            return "Bucket name must start with a letter or number"
        }
        if name.hasSuffix("-") || name.hasSuffix(".") {
            return "Bucket name must end with a letter or number"
        }
        return nil
    }

    /// Validates a user-provided path prefix for S3 object keys.
    /// Returns nil if valid, or an error message string if invalid.
    static func validatePathPrefix(_ prefix: String) -> String? {
        if prefix.isEmpty { return nil }
        if prefix.hasPrefix("/") { return "Path cannot start with /" }
        if prefix.hasSuffix("/") { return "Path cannot end with /" }
        if prefix.contains("//") { return "Path cannot contain //" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        if prefix.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Only letters, numbers, hyphens, underscores, dots, and slashes allowed"
        }
        if prefix.count > 256 { return "Path cannot exceed 256 characters" }
        return nil
    }
}
