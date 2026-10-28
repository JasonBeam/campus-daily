import Foundation
import Security
import WaterCore

enum CampusSharedCache {
    private static func query(_ service: String,_ account: String) -> [String:Any] {
        var query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        if let group = Bundle.main.object(forInfoDictionaryKey:"CampusKeychainGroup") as? String, !group.isEmpty {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
    static func read<T: Decodable>(_ type: T.Type, service: String = "CampusDaily.widget-cache.v1", account: String = "snapshot") -> T? {
        var request = query(service,account)
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var data: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary,&data) == errSecSuccess,
              let bytes = data as? Data, bytes.count <= 65536 else { return nil }
        return try? JSONDecoder().decode(type,from:bytes)
    }
    static func save(_ value: CampusSnapshot) throws {
        let key = query("CampusDaily.widget-cache.v1","snapshot")
        let changes: [String:Any] = [kSecValueData as String:try JSONEncoder().encode(value),kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(key as CFDictionary,changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = key; changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw CampusError.configuration }
        } else if status != errSecSuccess { throw CampusError.configuration }
    }
    static func clear() {
        SecItemDelete(query("CampusDaily.widget-cache.v1","snapshot") as CFDictionary)
    }
    static func config() -> CampusConfig? {
        read(CampusConfig.self,service:"CampusHotWater.campus-config.v1",account:"campus-config")
    }
}
