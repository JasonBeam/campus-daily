import Foundation
import Security
import WaterCore

enum WaterPlatformStore {
    private static var query: [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,
         kSecAttrService as String:"CampusHotWater.platform-profile.v1",kSecAttrAccount as String:"water-platform"]
    }
    static func load() throws -> WaterPlatformProfile? {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary,&result)
        if status == errSecItemNotFound {return nil}
        guard status == errSecSuccess, let bytes = result as? Data else {throw WaterError.storage}
        let value = try JSONDecoder().decode(WaterPlatformProfile.self,from:bytes)
        try value.validate(); return value
    }
    static func save(_ value: WaterPlatformProfile) throws {
        try value.validate()
        let changes: [String:Any] = [kSecValueData as String:try JSONEncoder().encode(value),
            kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary,changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; changes.forEach {item[$0.key] = $0.value}
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else {throw WaterError.storage}
        } else if status != errSecSuccess {throw WaterError.storage}
    }
}

enum PrivateConfigStore {
    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {throw WaterError.storage}
    }
    private static let service = "CampusHotWater.personal-config.v1"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "water-config"]
    }
    static func load() throws -> WaterConfig? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let config = try? JSONDecoder().decode(WaterConfig.self, from: data) else { throw WaterError.storage }
        try config.validate()
        return config
    }
    static func save(_ config: WaterConfig) throws {
        try config.validate()
        let data = try JSONEncoder().encode(config)
        let changes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw WaterError.storage }
        } else if status != errSecSuccess { throw WaterError.storage }
    }
}

@MainActor final class FileSessionStore: SessionStore {
    private let path: URL
    init() throws {
        var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("WaterSession", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        path = root.appendingPathComponent("session-v1.json")
    }
    func load() throws -> WaterSession? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try JSONDecoder().decode(WaterSession.self, from: Data(contentsOf: path))
    }
    func save(_ session: WaterSession) throws {
        try JSONEncoder().encode(session).write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
