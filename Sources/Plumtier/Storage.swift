import Foundation
import Security

/// A small place to keep bytes under a name. The SDK keeps the license in the Keychain, and
/// trial records in several stores at once.
protocol DataStore: Sendable
{
    func read(_ name: String) -> Data?
    func write(_ data: Data, _ name: String)
    func delete(_ name: String)
}

/// Generic password items in the user's Keychain. They survive deleting and reinstalling the app.
struct KeychainStore: DataStore
{
    let service: String

    private func query(_ name: String, modern: Bool) -> [String: Any]
    {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
        if modern
        {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// Runs `body` against the data protection keychain, and against the login keychain when the
    /// app isn't signed with the entitlements the first one needs (for example `swift run`).
    private func run(_ body: (_ modern: Bool) -> OSStatus) -> OSStatus
    {
        let status = body(true)
        return status == errSecMissingEntitlement ? body(false) : status
    }

    func read(_ name: String) -> Data?
    {
        // Without the entitlement a read answers "not found" rather than "missing entitlement",
        // so look in both keychains.
        for modern in [true, false]
        {
            var query = query(name, modern: modern)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data
            {
                return data
            }
        }
        return nil
    }

    func write(_ data: Data, _ name: String)
    {
        _ = run
        { modern in
            let query = query(name, modern: modern)
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecItemNotFound else
            {
                return status
            }
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete(_ name: String)
    {
        for modern in [true, false]
        {
            SecItemDelete(query(name, modern: modern) as CFDictionary)
        }
    }
}

/// Files in a folder, for example in Application Support.
struct FileStore: DataStore
{
    let folder: URL

    func read(_ name: String) -> Data?
    {
        try? Data(contentsOf: folder.appending(path: name))
    }

    func write(_ data: Data, _ name: String)
    {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appending(path: name), options: .atomic)
    }

    func delete(_ name: String)
    {
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }
}

/// Values in the app's user defaults.
struct DefaultsStore: DataStore
{
    let prefix: String

    func read(_ name: String) -> Data?
    {
        UserDefaults.standard.data(forKey: prefix + name)
    }

    func write(_ data: Data, _ name: String)
    {
        UserDefaults.standard.set(data, forKey: prefix + name)
    }

    func delete(_ name: String)
    {
        UserDefaults.standard.removeObject(forKey: prefix + name)
    }
}

/// Keeps values in memory. Used by tests and previews.
final class MemoryStore: DataStore, @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func read(_ name: String) -> Data?
    {
        lock.withLock { values[name] }
    }

    func write(_ data: Data, _ name: String)
    {
        lock.withLock { values[name] = data }
    }

    func delete(_ name: String)
    {
        lock.withLock { values[name] = nil }
    }
}
