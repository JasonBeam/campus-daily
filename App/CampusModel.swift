import Foundation
import Combine
import Security
import WidgetKit
import WaterCore

private enum CampusConfigStore {
    private static var query: [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,
         kSecAttrService as String:"CampusHotWater.campus-config.v1",kSecAttrAccount as String:"campus-config"]
    }
    static func load() throws -> CampusConfig? {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw WaterError.storage }
        let value = try JSONDecoder().decode(CampusConfig.self, from: data)
        try value.validate()
        return value
    }
    static func save(_ value: CampusConfig) throws {
        try value.validate()
        let changes: [String:Any] = [kSecValueData as String:try JSONEncoder().encode(value),
            kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw WaterError.storage }
        } else if status != errSecSuccess { throw WaterError.storage }
    }
}

@MainActor final class CampusModel: ObservableObject {
    @Published private(set) var configured = false
    @Published private(set) var loading = false
    @Published private(set) var snapshot: CampusSnapshot?
    @Published private(set) var issue: String?
    private var config: CampusConfig?
    private var lastAttempt: Date?
    private let provider = CampusProvider()
    private let cacheURL: URL
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CampusCache",isDirectory:true)
        cacheURL = directory.appendingPathComponent("last-good-v1.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
            var excluded = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            config = try CampusConfigStore.load(); configured = config != nil
            if let config, let data = try? Data(contentsOf: cacheURL),
               let cached = try? JSONDecoder().decode(CampusSnapshot.self, from:data),
               cached.owner == config.cacheIdentity { snapshot = cached }
        } catch { issue = "校园配置暂时无法读取，请解锁后重新打开 App" }
    }
    var room: String {
        let full = snapshot?.room ?? config?.dormRoom.nonEmpty ?? "未配置"
        if let address = PortalDormAddress.parse(full) {return address.shortRoom}
        let parts = full.components(separatedBy:" · ")
        if parts.count == 4, parts[1].hasSuffix("栋") {
            let building = String(parts[1].dropLast())
            let number = parts[3]
            if !building.isEmpty, !number.isEmpty, building.allSatisfy(\.isNumber), number.allSatisfy(\.isNumber) {
                return building + "栋" + number
            }
        }
        return full
    }
    var balanceText: String {
        guard let value = snapshot?.balance else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal; formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2; formatter.locale = Locale(identifier:"zh_CN")
        return formatter.string(from:NSDecimalNumber(decimal:value)) ?? "—"
    }
    var freshness: String {
        if loading { return "更新中" }
        if let snapshot, snapshot.balance != nil { return snapshot.balanceIsStale() ? "上次余额" : "已更新" }
        return configured ? "暂未获取" : "待配置"
    }
    var powerConfigured: Bool { config?.buildingID.isEmpty == false }
    func savePowerBinding(building: String, meter: CampusElectricity) throws {
        guard !loading, var next = config else { throw WaterError.busy }
        next.buildingID = building; next.meterID = meter.id
        try next.validate(); try CampusConfigStore.save(next)
        config = next
        snapshot = CampusSnapshot(owner:next.cacheIdentity)
        snapshot?.recordPower(.success(meter))
        saveSnapshot()
    }
    private func saveSnapshot() {
        guard let snapshot else { return }
        do {
            try JSONEncoder().encode(snapshot).write(to:cacheURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            try CampusSharedCache.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind:"CampusDailyBalances")
        }
        catch { issue = "余额已读取，本机缓存未保存" }
    }
    func importConfig(_ url: URL) throws {
        guard !loading else { throw WaterError.busy }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 32768 else { throw CampusError.configuration }
        let value = try JSONDecoder().decode(CampusConfig.self,from:Data(contentsOf:url))
        try value.validate()
        try CampusConfigStore.save(value)
        if config?.cacheIdentity != value.cacheIdentity { snapshot = nil; CampusSharedCache.clear(); WidgetCenter.shared.reloadTimelines(ofKind:"CampusDailyBalances") }
        config = value; configured = true; issue = nil; lastAttempt = nil
    }
    var onboardingLogin: CampusConfig? { config }
    func acceptLogin(_ value: CampusConfig) throws {
        guard !loading else { throw WaterError.busy }
        var next = value
        if let previous = config, previous.syscustid == value.syscustid, previous.areacode == value.areacode {
            next.buildingID = previous.buildingID; next.meterID = previous.meterID; next.dormRoom = previous.dormRoom
            if next.portalDormAddress.isEmpty {next.portalDormAddress = previous.portalDormAddress}
        }
        if next.dormRoom.isEmpty, let address = PortalDormAddress.parse(next.portalDormAddress) {next.dormRoom = address.shortRoom}
        try next.validate(); try CampusConfigStore.save(next)
        if config?.cacheIdentity != next.cacheIdentity { snapshot = nil; CampusSharedCache.clear(); WidgetCenter.shared.reloadTimelines(ofKind:"CampusDailyBalances") }
        config = next; configured = true; issue = nil; lastAttempt = nil
    }
    func saveDormName(_ room: String, power: CampusPowerSuggestion? = nil) throws {
        guard !loading, var next = config else { throw WaterError.busy }
        let changed = next.dormRoom != room
        next.dormRoom = room
        if let power {next.buildingID = power.building;next.meterID = power.meter.id}
        else if changed {next.buildingID = "";next.meterID = ""}
        try next.validate(); try CampusConfigStore.save(next)
        config = next
        if changed || power != nil {snapshot?.electricity = nil; snapshot?.powerFetchedAt = nil; snapshot?.powerError = nil}
        if let power {snapshot?.recordPower(.success(power.meter))}
        snapshot?.owner = next.cacheIdentity
        snapshot?.recordRoom(.success(room))
        saveSnapshot()
    }
    func importDevelopmentConfigIfPresent() {
        let root = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let file = root.appendingPathComponent("bootstrap.campusconfig")
        if FileManager.default.fileExists(atPath:file.path) {
            do { try importConfig(file); try FileManager.default.removeItem(at:file) }
            catch { issue = "校园配置导入失败，请检查格式" }
        }
        let powerFile = root.appendingPathComponent("bootstrap.campuspowerbinding")
        if let config, let data = try? Data(contentsOf:powerFile),
           let binding = try? JSONSerialization.jsonObject(with:data) as? [String:String],
           binding["syscustid"] == config.syscustid, binding["areacode"] == config.areacode,
           let building = binding["buildingID"], let meter = binding["meterID"] {
            var next = config; next.buildingID = building; next.meterID = meter
            if (try? CampusConfigStore.save(next)) != nil {
                self.config = next; snapshot = nil; lastAttempt = nil; CampusSharedCache.clear()
                try? FileManager.default.removeItem(at:powerFile)
            }
        }
        let cache = root.appendingPathComponent("bootstrap.campuscache")
        if let config, let bytes = try? Data(contentsOf:cache),
           let value = try? JSONDecoder().decode(CampusSnapshot.self,from:bytes),
           value.owner == config.cacheIdentity {
            if (snapshot?.balanceFetchedAt ?? .distantPast) < (value.balanceFetchedAt ?? .distantPast) {
                snapshot = value; saveSnapshot()
            }
            try? FileManager.default.removeItem(at:cache)
        }
    }
    func refresh(force: Bool = false) async {
        guard let config, !loading else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 300 { return }
        loading = true; lastAttempt = Date(); issue = nil
        defer { loading = false }
        if let shared = CampusSharedCache.read(CampusSnapshot.self), shared.owner == config.cacheIdentity,
           (shared.balanceFetchedAt ?? .distantPast) > (snapshot?.balanceFetchedAt ?? .distantPast) { snapshot = shared }
        var next = snapshot?.owner == config.cacheIdentity ? snapshot! : CampusSnapshot(owner:config.cacheIdentity)
        do { next.recordBalance(.success(try await provider.balance(config:config))) }
        catch { next.recordBalance(.failure((error as? CampusError) ?? .network)) }
        if !config.buildingID.isEmpty {
            // The selected meter already returns its room and remaining energy.
            // Reuse that one response, rather than querying the same room twice.
            do {
                let meter = try await provider.electricity(config:config)
                next.recordPower(.success(meter));next.recordRoom(.success(meter.room))
            } catch {
                let issue = (error as? CampusError) ?? .network
                next.recordPower(.failure(issue));next.recordRoom(.failure(issue))
            }
        } else {
            do { next.recordRoom(.success(try await provider.room(config:config))) }
            catch { next.recordRoom(.failure((error as? CampusError) ?? .network)) }
        }
        snapshot = next
        issue = next.cardError?.rawValue
        if issue == nil, next.room == nil, config.dormRoom.isEmpty { issue = next.roomError?.rawValue }
        saveSnapshot()
    }
    func importFailed(_ error: Error) { issue = (error as? CampusError)?.rawValue ?? "校园配置导入失败，请检查格式" }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
