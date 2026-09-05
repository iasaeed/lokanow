import Foundation
import Security
import LocalizeCore

enum Credentials {
    static let service = "com.lokanow.lokalise"
    static func read() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-token", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8) else { throw StudioError.message("Could not read the Lokalise token from Keychain (\(status)).") }
        return token
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-token"]
        if token.isEmpty { let status = SecItemDelete(query as CFDictionary); guard [errSecSuccess, errSecItemNotFound].contains(status) else { throw StudioError.message("Could not remove the Keychain credential.") }; return }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query; attributes.forEach { addition[$0.key] = $0.value }
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw StudioError.message("Could not save the token to Keychain.") }
        } else if status != errSecSuccess { throw StudioError.message("Could not update the Keychain credential (\(status)).") }
    }
}
struct SavedProject: Codable {
    var options: [String: ModuleOptions] = [:]
    var excludedFindings: Set<String> = []
    var selectedModules: Set<String> = []
    var removedModules: Set<String>? = nil
    var remoteMappings: [String: Int] = [:]
    var exclusions: String = ""
    var wrappers: String = ""
}
enum Storage {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lokanow")
    }
    static func save<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + ".json")
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func load<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        let url = directory.appendingPathComponent(name + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    static func clearCache() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.lastPathComponent.hasPrefix("cache-") { try FileManager.default.removeItem(at: url) }
    }
}
