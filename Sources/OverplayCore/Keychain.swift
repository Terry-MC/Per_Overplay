import Foundation
import Security

public protocol CredentialStore {
    func setCredential(_ credential: String, accountId: String) throws
    func credential(accountId: String) throws -> String?
    func hasCredential(accountId: String) -> Bool
    func deleteCredential(accountId: String) throws
    func deleteAll() throws
}

public struct KeychainError: Error, CustomStringConvertible {
    public let status: OSStatus
    public let operation: String
    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Keychain \(operation)失败：\(message)"
    }
}

public final class KeychainCredentialStore: CredentialStore {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "local.ds.overplay.credentials", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery(accountId: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        if let accountId {
            query[kSecAttrAccount as String] = accountId
        }
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func setCredential(_ credential: String, accountId: String) throws {
        let data = Data(credential.utf8)
        let query = baseQuery(accountId: accountId)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw KeychainError(status: updateStatus, operation: "更新")
        }
        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus, operation: "写入")
        }
    }

    public func credential(accountId: String) throws -> String? {
        var query = baseQuery(accountId: accountId)
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError(status: status, operation: "读取")
        }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode, operation: "解码")
        }
        return text
    }

    public func hasCredential(accountId: String) -> Bool {
        (try? credential(accountId: accountId))?.isEmpty == false
    }

    public func deleteCredential(accountId: String) throws {
        let status = SecItemDelete(baseQuery(accountId: accountId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, operation: "删除")
        }
    }

    public func deleteAll() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, operation: "批量删除")
        }
    }
}

public final class InMemoryCredentialStore: CredentialStore {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func setCredential(_ credential: String, accountId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[accountId] = credential
    }

    public func credential(accountId: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[accountId]
    }

    public func hasCredential(accountId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values[accountId]?.isEmpty == false
    }

    public func deleteCredential(accountId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: accountId)
    }

    public func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}
