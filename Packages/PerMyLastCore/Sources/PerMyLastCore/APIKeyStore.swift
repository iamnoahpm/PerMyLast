import Foundation
import Security

/// Where the user's own Anthropic key lives (FR-A12).
public protocol APIKeyStore: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

public struct KeychainError: Error, LocalizedError, Equatable {
    public let status: OSStatus
    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// The macOS Keychain, generic-password item, readable after first unlock.
public struct KeychainAPIKeyStore: APIKeyStore {
    private let service: String
    private let account: String

    public init(service: String = "app.permylast.anthropic-api-key", account: String = "default") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    public func save(_ key: String) throws {
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// For tests and previews.
public final class InMemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    public init(key: String? = nil) { self.key = key }
    public func load() throws -> String? { lock.withLock { key } }
    public func save(_ key: String) throws { lock.withLock { self.key = key } }
    public func delete() throws { lock.withLock { key = nil } }
}

public enum APIKeyMigration {
    /// Moves a key saved by an earlier build (app preferences) into the store, once.
    /// The old copy is removed only after the new one reads back correctly; if
    /// anything fails the old key keeps working and the error is returned.
    public static func migrate(legacy: String?, store: any APIKeyStore, clearLegacy: () -> Void) -> (key: String, error: Error?) {
        let old = legacy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stored: String?
        do { stored = try store.load() } catch { return (old, error) }

        if let stored, !stored.isEmpty {
            if legacy != nil { clearLegacy() }
            return (stored, nil)
        }
        guard !old.isEmpty else {
            if legacy != nil { clearLegacy() }
            return ("", nil)
        }
        do {
            try store.save(old)
            guard try store.load() == old else { throw KeychainError(status: errSecInternalError) }
            clearLegacy()
            return (old, nil)
        } catch {
            return (old, error)
        }
    }
}
