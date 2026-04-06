import Foundation
import Security

// MARK: - KeychainError

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error: \(message)"
            }
            return "Keychain error: \(status)"
        }
    }
}

// MARK: - KeychainService

struct KeychainService {

    private static let service = "com.healthpush.app.destinations"
    private static let missingEntitlementStatus: OSStatus = -34018
    private static let fallbackStore = InMemorySecretStore()

    static func destinationSecretKey(destinationID: UUID, field: String) -> String {
        "destination.\(destinationID.uuidString.lowercased()).\(field)"
    }

    static func save(_ value: String, for key: String) throws {
        if shouldUseFallbackStore {
            fallbackStore.save(value, for: key)
            return
        }

        let encodedValue = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = encodedValue
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == missingEntitlementStatus && isRunningTests {
            fallbackStore.save(value, for: key)
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func load(_ key: String) throws -> String? {
        if shouldUseFallbackStore {
            return fallbackStore.load(key)
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        case missingEntitlementStatus where isRunningTests:
            return fallbackStore.load(key)
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func delete(_ key: String) throws {
        if shouldUseFallbackStore {
            fallbackStore.delete(key)
            return
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == missingEntitlementStatus && isRunningTests {
            fallbackStore.delete(key)
            return
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static var shouldUseFallbackStore: Bool {
        isRunningTests
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

// MARK: - InMemorySecretStore

private final class InMemorySecretStore: @unchecked Sendable {

    private let lock = NSLock()
    private var values: [String: String] = [:]

    func save(_ value: String, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func load(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func delete(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
