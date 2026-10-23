import Foundation
import Combine
import Security
import CryptoKit
import WaterCore

@MainActor final class LaundryModel: ObservableObject {
    @Published private(set) var configured = false
    @Published private(set) var accountConnected = false
    @Published private(set) var loading = false
    @Published private(set) var snapshot: LaundrySnapshot?
    @Published private(set) var issue: String?
    @Published private(set) var checkout: LaundryCheckoutRecord?
    @Published private(set) var checkoutBusy = false
    @Published private(set) var checkoutIssue: String?
    @Published private(set) var checkoutProgress: String?
    @Published private(set) var savedMachines: [SavedWasher] = []
    @Published private(set) var candidate: LaundrySnapshot?
    private var candidateConfig: LaundryConfig?
    var selectedMachineID: String? { config?.deviceId }
    private var controller: LaundryCheckoutController?
    private var config: LaundryConfig?
    private var connection: UjingConnection?
    private var lastAttempt: Date?
    private let provider = LaundryProvider { path, status, data in
        // Own transaction responses only; never persist request credentials or SDK callbacks.
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("LaundryCache",isDirectory:true)
        let name = path.hasPrefix("/api/v1/payment/arguments") ? "last-payment-response" : "last-create-response"
        guard data.count <= 1_048_576 else { return }
        try? data.write(to:folder.appendingPathComponent(name + ".json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        let meta: [String:Any] = ["path":path.components(separatedBy:"?")[0],"status":status,"receivedAt":ISO8601DateFormatter().string(from:Date())]
        if let bytes = try? JSONSerialization.data(withJSONObject:meta) {
            try? bytes.write(to:folder.appendingPathComponent(name + "-metadata.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    private let key: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:"CampusHotWater.laundry.v1",kSecAttrAccount as String:"laundry-config"]
    private let cacheURL: URL
    private var snapshotURL: URL {
        guard let config else { return cacheURL }
        let device = SHA256.hash(data:Data(config.deviceId.utf8)).map { String(format:"%02x",$0) }.joined()
        return cacheURL.deletingLastPathComponent().appendingPathComponent("last-good-" + config.credentialIdentity + "-" + device + ".json")
    }
    init() {
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("LaundryCache",isDirectory:true)
        cacheURL = folder.appendingPathComponent("last-good-v1.json")
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,
                attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
            var excluded = folder; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            controller = try LaundryCheckoutController(store:LaundryFileStore(folder:folder),api:provider)
            checkout = controller?.record
            var query = key; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary,&result)
            if let stored = try UjingConnectionStore.load() {
                connection = stored; accountConnected = true; config = stored.config; configured = config != nil
                savedMachines = try readAccountMachines(stored.account)
                if let value = config {
                    checkout = controller?.record?.belongs(to:value) == true ? controller?.record : nil
                    if let data = try? Data(contentsOf:snapshotURL), let cached = try? JSONDecoder().decode(LaundrySnapshot.self,from:data), cached.deviceId == value.deviceId { snapshot = cached }
                }
                else { checkout = nil }
            } else if status == errSecSuccess, let bytes = result as? Data {
                let value = try JSONDecoder().decode(LaundryConfig.self,from:bytes); try value.validate()
                config = value; configured = true; accountConnected = true
                savedMachines = try loadMachines(value)
                try controller?.associateLegacyAccount(config:value)
                checkout = controller?.record?.belongs(to:value) == true ? controller?.record : nil
                if let data = (try? Data(contentsOf:snapshotURL)) ?? (try? Data(contentsOf:cacheURL)),
                   let old = try? JSONDecoder().decode(LaundrySnapshot.self,from:data), old.deviceId == value.deviceId { snapshot = old }
            } else if status != errSecItemNotFound { issue = "请解锁后重新打开 App 读取洗衣配置" }
        } catch { issue = "洗衣配置暂时无法读取" }
    }
    func importConfig(_ url: URL) throws {
        guard mayImport else { throw WaterError.busy }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 32768 else { throw LaundryError.configuration }
        let bytes = try Data(contentsOf:url)
        let value = try JSONDecoder().decode(LaundryConfig.self,from:bytes); try value.validate()
        let machines = try loadMachines(value)
        try writeConfig(value,legacy:true)
        if connection != nil { try UjingConnectionStore.clear(); connection = nil }
        snapshot = nil; try? FileManager.default.removeItem(at:cacheURL)
        config = value; savedMachines = machines; configured = true; accountConnected = true; issue = nil; lastAttempt = nil
        checkout = controller?.record?.belongs(to:value) == true ? controller?.record : nil
    }
    private func writeConfig(_ value: LaundryConfig, legacy: Bool = false, selectionName: String? = nil) throws {
        try value.validate()
        if !legacy, var connected = connection, value.accountID == connected.account.id {
            let name = selectionName ?? savedMachines.first(where:{ $0.id == value.deviceId })?.name ?? "常用洗衣机"
            connected.selected = SavedWasher(id:value.deviceId,qrCode:value.qrCode,name:name)
            try UjingConnectionStore.save(connected); connection = connected; return
        }
        let changes: [String:Any] = [kSecValueData as String:try JSONEncoder().encode(value),
            kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(key as CFDictionary,changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = key; changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw WaterError.storage }
        } else if status != errSecSuccess { throw WaterError.storage }
    }
    private func machineFile(_ value: LaundryConfig) throws -> URL {
        return try libraryFile(owner:value.credentialIdentity)
    }
    private func libraryFile(owner: String) throws -> URL {
        let folder = cacheURL.deletingLastPathComponent().appendingPathComponent("WasherLibraries",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
        return folder.appendingPathComponent(owner + ".json")
    }
    private func accountLibraryFile(_ account: UjingAccount) throws -> URL {
        let owner = SHA256.hash(data:Data(("account:" + account.id).utf8)).map { String(format:"%02x",$0) }.joined()
        return try libraryFile(owner:owner)
    }
    private func readAccountMachines(_ account: UjingAccount) throws -> [SavedWasher] {
        let file = try accountLibraryFile(account)
        guard FileManager.default.fileExists(atPath:file.path) else { return [] }
        let data = try Data(contentsOf:file)
        guard data.count <= 262144 else { throw LaundryError.configuration }
        let list = try JSONDecoder().decode([SavedWasher].self,from:data)
        guard list.count <= 50, Set(list.map(\.id)).count == list.count else { throw LaundryError.configuration }
        for item in list { try WasherQRCode.validate(item.qrCode) }
        return list
    }
    /// JWT payload is used ONLY to retain existing local machine preferences after a verified login.
    /// Server-issued credentials and server responses still authorize every request.
    private func legacyPreferenceAccount(_ config: LaundryConfig) -> String? {
        let token = config.headers.first { $0.key.lowercased() == "authorization" }?.value ?? ""
        let pieces = token.replacingOccurrences(of:"Bearer ",with:"").split(separator:".")
        guard pieces.count == 3 else { return nil }
        var text = String(pieces[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        text += String(repeating:"=",count:(4-text.count%4)%4)
        guard let bytes = Data(base64Encoded:text), bytes.count <= 8192,
              let body = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { return nil }
        if let id = body["appUserId"] as? String { return id }
        return (body["appUserId"] as? NSNumber)?.stringValue
    }
    func connect(_ account: UjingAccount) throws {
        guard mayImport else { throw WaterError.unresolved }
        try account.validate()
        let old = config
        let sameAccount = connection?.account.id == account.id || old.map { legacyPreferenceAccount($0) == account.id } == true
        var list = try readAccountMachines(account)
        if sameAccount {
            for item in savedMachines where !list.contains(where:{ $0.id == item.id }) { list.append(item) }
        }
        let selected = sameAccount ? list.first(where:{ $0.id == old?.deviceId }) ?? list.first : list.first
        let next = UjingConnection(account:account,selected:selected)
        if let config = next.config { try writeMachines(list,config:config) }
        else { try JSONEncoder().encode(list).write(to:accountLibraryFile(account),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }
        try UjingConnectionStore.save(next)
        connection = next; config = next.config; accountConnected = true; configured = config != nil
        savedMachines = list; candidate = nil; candidateConfig = nil; issue = nil; checkoutIssue = nil; lastAttempt = nil
        if !sameAccount || old?.deviceId != config?.deviceId { snapshot = nil }
        if sameAccount, let old, let config {
            do { try controller?.migrateCompletedAccount(from:old,to:config) }
            catch { checkoutIssue = "登录已保存，旧订单记录保留待核对" }
        }
        checkout = config.flatMap { value in controller?.record?.belongs(to:value) == true ? controller?.record : nil }
        if configured { Task { await refresh(force:true) } }
    }
    private func writeMachines(_ list: [SavedWasher], config value: LaundryConfig) throws {
        guard list.count <= 50, Set(list.map(\.id)).count == list.count else { throw LaundryError.configuration }
        for item in list {
            try WasherQRCode.validate(item.qrCode)
            guard !item.id.isEmpty, item.id.count <= 128, !item.name.isEmpty, item.name.count <= 40,
                  item.name.rangeOfCharacter(from:.controlCharacters) == nil else { throw LaundryError.configuration }
        }
        try JSONEncoder().encode(list).write(to:machineFile(value),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
    private func loadMachines(_ value: LaundryConfig) throws -> [SavedWasher] {
        let file = try machineFile(value)
        var list: [SavedWasher] = []
        if FileManager.default.fileExists(atPath:file.path) {
            let data = try Data(contentsOf:file)
            guard data.count <= 262144 else { throw LaundryError.configuration }
            list = try JSONDecoder().decode([SavedWasher].self,from:data)
        }
        if !list.contains(where:{ $0.id == value.deviceId }) {
            list.append(SavedWasher(id:value.deviceId,qrCode:value.qrCode,name:"常用洗衣机"))
        }
        try writeMachines(list,config:value)
        return list
    }
    func prepareMachine(qrCode: String) async {
        guard mayImport else { issue = "请先核对已有洗衣订单"; return }
        guard let headers = connection?.account.headers ?? config?.headers else { issue = "请先登录 U净，再添加洗衣机"; return }
        loading = true; issue = nil; candidate = nil; candidateConfig = nil
        defer { loading = false }
        do {
            let (resolved,value) = try await provider.discover(headers:headers,accountID:connection?.account.id ?? config?.accountID,qrCode:qrCode)
            candidateConfig = resolved; candidate = value
        } catch { issue = (error as? LocalizedError)?.errorDescription ?? "无法识别这台洗衣机，请核对二维码" }
    }
    func savePreparedMachine(name: String) throws {
        guard mayImport, let value = candidateConfig, let snapshot = candidate else { throw WaterError.busy }
        let alias = name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !alias.isEmpty, alias.count <= 40, alias.rangeOfCharacter(from:.controlCharacters) == nil else { throw LaundryError.configuration }
        var list = savedMachines
        if let index = list.firstIndex(where:{ $0.id == value.deviceId }) { list[index] = SavedWasher(id:value.deviceId,qrCode:value.qrCode,name:alias,savedAt:list[index].savedAt) }
        else { list.append(SavedWasher(id:value.deviceId,qrCode:value.qrCode,name:alias)) }
        try writeMachines(list,config:value); try writeConfig(value,selectionName:alias)
        config = value; configured = true; accountConnected = true; self.snapshot = snapshot; savedMachines = list
        checkout = controller?.record?.belongs(to:value) == true ? controller?.record : nil
        candidateConfig = nil; candidate = nil; issue = nil; checkoutIssue = nil; lastAttempt = nil
    }
    func selectMachine(_ item: SavedWasher) throws {
        guard mayImport, let config, savedMachines.contains(where:{ $0.id == item.id }) else { throw WaterError.busy }
        let value = LaundryConfig(headers:config.headers,qrCode:item.qrCode,deviceId:item.id,accountID:config.accountID)
        try writeConfig(value)
        self.config = value; snapshot = nil; issue = nil; checkoutIssue = nil; lastAttempt = nil
        checkout = controller?.record?.belongs(to:value) == true ? controller?.record : nil
        // Trigger publication even if the list is unchanged, since selection lives in the keychain config.
        savedMachines = Array(savedMachines)
    }
    func importDevelopmentConfigIfPresent() {
        let file = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("bootstrap.laundryconfig")
        guard FileManager.default.fileExists(atPath:file.path) else { return }
        do { try importConfig(file); try FileManager.default.removeItem(at:file) }
        catch { issue = "洗衣配置导入失败，请检查格式" }
    }
    func recoverDevelopmentOrderIfPresent() async {
        let file = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("bootstrap.laundryrecovery")
        guard FileManager.default.fileExists(atPath:file.path), let config, let controller else { return }
        do {
            struct Recovery: Decodable { let orderId: String }
            let bytes = try Data(contentsOf:file)
            guard bytes.count < 1024 else { throw LaundryError.configuration }
            let recovery = try JSONDecoder().decode(Recovery.self,from:bytes)
            try await controller.recover(config:config,candidateOrderId:recovery.orderId)
            checkout = controller.record; checkoutIssue = nil
            try FileManager.default.removeItem(at:file)
        } catch { checkoutIssue = "旧预约恢复未完成，请刷新订单核对" }
    }
    func refresh(force: Bool = false) async {
        guard let config, !loading else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        loading = true; issue = nil; lastAttempt = Date()
        defer { loading = false }
        do {
            let value = try await provider.query(config:config)
            snapshot = value
            do { try JSONEncoder().encode(value).write(to:snapshotURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }
            catch { issue = "已更新，本机缓存未保存" }
        } catch { issue = (error as? LaundryError)?.rawValue ?? "洗衣查询失败，保留上次结果" }
    }
    func importFailed() { issue = "洗衣配置导入失败，请检查文件" }
    var mayImport: Bool { !loading && !checkoutBusy && (controller?.record == nil || controller?.record?.stage == .completed) }
    var mayCreate: Bool {
        guard controller != nil, configured, !checkoutBusy, !loading, issue == nil,
              let snapshot, snapshot.moduleType == 7, snapshot.status == 0,
              snapshot.createOrderEnabled, snapshot.activeOrderId == nil,
              snapshot.storeId != nil, snapshot.deviceTypeId != nil else { return false }
        return checkout == nil || checkout?.stage == .completed
    }
    var deviceStateText: String {
        if let checkout, checkout.stage != .completed {
            if checkout.order?.running == true { return "洗衣中" }
            if checkout.order?.paid == true { return "待启动" }
            if checkout.stage == .creating { return "核对中" }
            if checkout.stage == .paymentRequested { return "付款待确认" }
            if checkout.stage == .cancellationRequested { return "取消待确认" }
            return "已预约"
        }
        guard let snapshot else { return "待查询" }
        return freshness == "已更新" ? snapshot.stateLabel : "上次" + snapshot.stateLabel
    }
    func createAndPay(_ selected: LaundryProgram) async {
        // A fresh explicit “下单并前往支付宝” confirmation authorizes this sequence.
        // A recovered/uncertain creation stops at the order card for a new confirmation.
        checkoutProgress = "正在预约并核对机器…"
        guard await create(selected) else { checkoutProgress = nil; return }
        checkoutProgress = "订单已确认，正在准备支付宝…"
        await pay()
    }
    @discardableResult private func create(_ selected: LaundryProgram) async -> Bool {
        guard mayCreate, let config, let controller, let snapshot else { return false }
        checkoutBusy = true; checkoutIssue = nil
        defer { checkout = controller.record; checkoutBusy = false }
        do { try await controller.create(config:config,snapshot:snapshot,program:selected); return true }
        catch {
            checkoutProgress = nil
            checkoutIssue = (error as? LocalizedError)?.errorDescription ?? "订单结果待核对，请勿重复下单"
            if controller.record?.stage == .creating {
                do {
                    if controller.record?.orderId != nil { try await controller.refresh(config:config) }
                    else if let id = try await provider.activeOrderID(config:config) { try await controller.recover(config:config,candidateOrderId:id) }
                    if controller.record?.stage != .creating { checkoutIssue = nil }
                } catch { /* Keep the durable unresolved record. */ }
            }
            return false
        }
    }
    func pay() async {
        guard !checkoutBusy, let config, let controller, let record = controller.record else { return }
        checkoutBusy = true; checkoutIssue = nil; checkoutProgress = "正在获取支付宝付款入口…"
        defer { checkout = controller.record; checkoutBusy = false }
        do {
            let payment = try await controller.payment(config:config)
            switch try payment.destination(maximum:record.expectedPrice) {
            case .query:
                try await controller.refresh(config:config)
                checkoutProgress = nil
            case .sdk(let signed):
                checkoutProgress = "正在打开支付宝…"
                AlipayBridge.shared.pay(signed) { [weak self] status, memo in
                    Task {
                        self?.checkoutProgress = "正在核对订单状态…"
                        await self?.refreshOrder()
                        self?.checkoutProgress = nil
                        if status == "6001" { self?.checkoutIssue = "你已退出支付宝付款，请核对订单状态" }
                        else if status != "9000" && status != "8000" {
                            self?.checkoutIssue = memo.isEmpty ? "支付宝未完成付款，请核对订单状态" : "支付宝返回：" + String(memo.prefix(160))
                        }
                    }
                }
            case .checkout(let url):
                checkoutProgress = "正在打开支付宝…"
                AlipayBridge.shared.openCheckout(url) { [weak self] opened in
                    if opened { self?.checkoutProgress = "已打开支付宝，完成后返回核对订单" }
                    else {
                        self?.checkoutProgress = nil
                        self?.checkoutIssue = "未能打开支付宝收银台，请核对订单状态"
                    }
                }
            }
        } catch {
            checkoutProgress = nil
            checkoutIssue = (error as? LocalizedError)?.errorDescription ?? "付款结果待核对，请刷新订单"
        }
    }
    var mayCancel: Bool {
        guard !checkoutBusy, let record = checkout, [.created,.paymentRequested].contains(record.stage),
              let order = record.order, order.payFlag?.text == "0" else { return false }
        return ["10","17"].contains(order.status.text)
    }
    func cancelOrder() async {
        guard mayCancel, let config, let controller else { return }
        checkoutBusy = true; checkoutIssue = nil; checkoutProgress = nil
        defer { checkout = controller.record; checkoutBusy = false }
        do { try await controller.cancel(config:config) }
        catch { checkoutIssue = (error as? LocalizedError)?.errorDescription ?? "取消结果待核对，请刷新订单" }
        await refresh(force:true)
    }
    func refreshOrder() async {
        guard !checkoutBusy, let config, let controller, controller.record?.belongs(to:config) == true else { return }
        checkoutBusy = true; checkoutIssue = nil; checkoutProgress = "正在核对订单状态…"
        defer { checkout = controller.record; checkoutBusy = false; checkoutProgress = nil }
        do {
            if controller.record?.orderId != nil { try await controller.refresh(config:config) }
            else if let id = try await provider.activeOrderID(config:config) { try await controller.recover(config:config,candidateOrderId:id) }
            else { checkoutIssue = "暂未查到对应预约，请在U净订单核对；未重复提交" }
            if let record = controller.record, record.stage == .created, let id = record.orderId,
               let order = record.order, ["10","17"].contains(order.status.text), order.payFlag?.text == "0" {
                await provider.preparePayment(config:config,id:id)
            }
        }
        catch {
            checkoutProgress = nil
            checkoutIssue = (error as? LocalizedError)?.errorDescription ?? "订单查询失败，保留上次状态"
        }
    }
    var freshness: String {
        guard let snapshot else { return "暂未查询" }
        return issue != nil || Date().timeIntervalSince(snapshot.fetchedAt) >= 60 ? "上次查询" : "已更新"
    }
}

@MainActor private final class LaundryFileStore: LaundryCheckoutStore {
    let file: URL
    init(folder: URL) { file = folder.appendingPathComponent("checkout-v1.json") }
    func load() throws -> LaundryCheckoutRecord? {
        guard FileManager.default.fileExists(atPath:file.path) else { return nil }
        return try JSONDecoder().decode(LaundryCheckoutRecord.self,from:Data(contentsOf:file))
    }
    func save(_ value: LaundryCheckoutRecord) throws {
        try JSONEncoder().encode(value).write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}
