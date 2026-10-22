import Foundation
import Combine
import Security
import WaterCore

@MainActor final class LaundryModel: ObservableObject {
    @Published private(set) var configured = false
    @Published private(set) var loading = false
    @Published private(set) var snapshot: LaundrySnapshot?
    @Published private(set) var issue: String?
    @Published private(set) var checkout: LaundryCheckoutRecord?
    @Published private(set) var checkoutBusy = false
    @Published private(set) var checkoutIssue: String?
    private var controller: LaundryCheckoutController?
    private var config: LaundryConfig?
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
            if status == errSecSuccess, let bytes = result as? Data {
                let value = try JSONDecoder().decode(LaundryConfig.self,from:bytes); try value.validate()
                config = value; configured = true
                if let data = try? Data(contentsOf:cacheURL),
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
        let changes: [String:Any] = [kSecValueData as String:try JSONEncoder().encode(value),
            kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(key as CFDictionary,changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = key; changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw WaterError.storage }
        } else if status != errSecSuccess { throw WaterError.storage }
        snapshot = nil; try? FileManager.default.removeItem(at:cacheURL)
        config = value; configured = true; issue = nil; lastAttempt = nil
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
            do { try JSONEncoder().encode(value).write(to:cacheURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }
            catch { issue = "已更新，本机缓存未保存" }
        } catch { issue = (error as? LaundryError)?.rawValue ?? "洗衣查询失败，保留上次结果" }
    }
    func importFailed() { issue = "洗衣配置导入失败，请检查文件" }
    var mayImport: Bool { !loading && !checkoutBusy && (checkout == nil || checkout?.stage == .completed) }
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
        guard await create(selected) else { return }
        await pay()
    }
    @discardableResult private func create(_ selected: LaundryProgram) async -> Bool {
        guard mayCreate, let config, let controller, let snapshot else { return false }
        checkoutBusy = true; checkoutIssue = nil
        defer { checkout = controller.record; checkoutBusy = false }
        do { try await controller.create(config:config,snapshot:snapshot,program:selected); return true }
        catch {
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
        checkoutBusy = true; checkoutIssue = nil
        defer { checkout = controller.record; checkoutBusy = false }
        do {
            let payment = try await controller.payment(config:config)
            switch try payment.destination(maximum:record.expectedPrice) {
            case .query:
                try await controller.refresh(config:config)
            case .sdk(let signed):
                AlipayBridge.shared.pay(signed) { [weak self] status, memo in
                    Task {
                        await self?.refreshOrder()
                        if status == "6001" { self?.checkoutIssue = "你已退出支付宝付款，请核对订单状态" }
                        else if status != "9000" && status != "8000" {
                            self?.checkoutIssue = memo.isEmpty ? "支付宝未完成付款，请核对订单状态" : "支付宝返回：" + String(memo.prefix(160))
                        }
                    }
                }
            case .checkout(let url):
                AlipayBridge.shared.openCheckout(url) { [weak self] opened in
                    if !opened { self?.checkoutIssue = "未能打开支付宝收银台，请核对订单状态" }
                }
            }
        } catch { checkoutIssue = (error as? LocalizedError)?.errorDescription ?? "付款结果待核对，请刷新订单" }
    }
    var mayCancel: Bool {
        guard !checkoutBusy, let record = checkout, [.created,.paymentRequested].contains(record.stage),
              let order = record.order, order.payFlag?.text == "0" else { return false }
        return ["10","17"].contains(order.status.text)
    }
    func cancelOrder() async {
        guard mayCancel, let config, let controller else { return }
        checkoutBusy = true; checkoutIssue = nil
        defer { checkout = controller.record; checkoutBusy = false }
        do { try await controller.cancel(config:config) }
        catch { checkoutIssue = (error as? LocalizedError)?.errorDescription ?? "取消结果待核对，请刷新订单" }
        await refresh(force:true)
    }
    func refreshOrder() async {
        guard !checkoutBusy, let config, let controller, controller.record != nil else { return }
        checkoutBusy = true; checkoutIssue = nil
        defer { checkout = controller.record; checkoutBusy = false }
        do {
            if controller.record?.orderId != nil { try await controller.refresh(config:config) }
            else if let id = try await provider.activeOrderID(config:config) { try await controller.recover(config:config,candidateOrderId:id) }
            else { checkoutIssue = "暂未查到对应预约，请在U净订单核对；未重复提交" }
            if let record = controller.record, record.stage == .created, let id = record.orderId,
               let order = record.order, ["10","17"].contains(order.status.text), order.payFlag?.text == "0" {
                await provider.preparePayment(config:config,id:id)
            }
        }
        catch { checkoutIssue = (error as? LocalizedError)?.errorDescription ?? "订单查询失败，保留上次状态" }
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
