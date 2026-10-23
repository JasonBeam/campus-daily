import Foundation

public struct LaundryScalar: Codable, Sendable {
    public let text: String
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s }
        else { text = String(try c.decode(Int64.self)) }
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(text) }
}

public struct LaundryOrder: Codable, Sendable {
    public let orderId: LaundryScalar
    public let deviceId: String
    public let status: LaundryScalar
    public let payFlag: LaundryScalar?
    public let statusRemark: String?
    public let remainTime: Int?
    public let deviceWashModelId: Int?
    public let createAt: String?
    public let payPrice: Decimal?
    public let countDown: Int?
    public var id: String { orderId.text }
    public var paid: Bool { payFlag?.text == "1" }
    public var terminal: Bool { ["50","51","52","53"].contains(status.text) }
    public var running: Bool { ["21","22","24","29","30","35","40"].contains(status.text) }
    public var label: String {
        switch status.text {
        case "10": return "已预约 · 待付款"
        case "17": return "待付款"
        case "20": return "已付款，等待启动"
        case "21": return "正在启动"
        case "40": return "洗衣中"
        case "50": return "洗衣完成"
        case "51": return "付款已超时"
        case "52": return "启动失败，请查看U净订单"
        case "53": return "订单已取消"
        default: return statusRemark?.isEmpty == false ? statusRemark! : "订单状态待核对"
        }
    }
}

/// Creation can return only a receipt; detail fields are queried separately.
public struct LaundryCreatedOrder: Decodable, Sendable {
    public let orderId: LaundryScalar
    public var id: String { orderId.text }
    private enum CodingKeys: String, CodingKey { case orderId, id }
    public init(from decoder: Decoder) throws {
        if let keys = try? decoder.container(keyedBy:CodingKeys.self) {
            orderId = try keys.decodeIfPresent(LaundryScalar.self,forKey:.orderId) ?? keys.decode(LaundryScalar.self,forKey:.id)
        } else { orderId = try LaundryScalar(from:decoder) }
    }
}

public struct LaundryPayment: Decodable, Sendable {
    public enum Destination: Equatable, Sendable {
        case query, checkout(URL), sdk(String)
    }
    public struct Info: Decodable, Sendable { public let orderInfo: String? }
    public let payInfo: Info?
    public let orderInfo: String?
    public let skipPay: Bool?
    public let jumpToQuery: Bool?
    public let checkoutURL: URL?
    private enum CodingKeys: String, CodingKey { case payInfo, orderInfo, skipPay, jumpToQuery }
    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy:CodingKeys.self)
        payInfo = try? keys.decodeIfPresent(Info.self,forKey:.payInfo)
        orderInfo = try? keys.decodeIfPresent(String.self,forKey:.orderInfo)
        func flag(_ key: CodingKeys) -> Bool? {
            if let value = try? keys.decode(Bool.self,forKey:key) { return value }
            if let value = try? keys.decode(Int.self,forKey:key), [0,1].contains(value) { return value == 1 }
            if let value = try? keys.decode(String.self,forKey:key), ["0","1","true","false"].contains(value) { return value == "1" || value == "true" }
            return nil
        }
        skipPay = flag(.skipPay); jumpToQuery = flag(.jumpToQuery)
        checkoutURL = try PaymentJSON(from:decoder).alipayURL
    }
    public var signedOrder: String? { payInfo?.orderInfo?.isEmpty == false ? payInfo?.orderInfo : orderInfo }
    public static func isAllowedCheckoutURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url:url,resolvingAgainstBaseURL:false),
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else { return false }
        if parts.scheme == "https", parts.host == "qr.alipay.com", !parts.path.isEmpty { return true }
        // Observed U净 F2F response: preserve the server-issued link, including its opaque authorization state.
        guard parts.scheme == "alipays", parts.host == "platformapi", parts.path == "/startApp",
              let items = parts.queryItems, Set(items.map(\.name)).count == items.count else { return false }
        let values = Dictionary(uniqueKeysWithValues:items.map { ($0.name,$0.value ?? "") })
        guard values["appId"] == "20000042", values["actionType"] == "WebView", values["followType"] == "PUBLIC",
              let nested = values["url"], let auth = URLComponents(string:nested),
              auth.scheme == "https", auth.host == "openauth.alipay.com", auth.path == "/oauth2/publicAppAuthorize.htm",
              auth.user == nil, auth.password == nil, auth.port == nil, auth.fragment == nil,
              let query = auth.queryItems, Set(query.map(\.name)).count == query.count,
              let redirect = query.first(where: { $0.name == "redirect_uri" })?.value,
              let target = URLComponents(string:redirect), target.scheme == "https", target.host == "wx.zhinengxiyifang.cn",
              target.path == "/static/commonWasher/index.html", target.user == nil, target.password == nil,
              target.port == nil, target.fragment == nil else { return false }
        return true
    }
    public func destination(maximum: Decimal) throws -> Destination {
        if skipPay == true || jumpToQuery == true { return .query }
        // A QR checkout can itself occupy orderInfo; do not feed that URL to the app-pay SDK.
        if let checkoutURL { return .checkout(checkoutURL) }
        if let signed = signedOrder, Self.validSignedOrder(signed,maximum:maximum) { return .sdk(signed) }
        throw LaundryCheckoutError.checkoutUnavailable
    }
    public static func validSignedOrder(_ value: String, maximum: Decimal) -> Bool {
        guard let parts = URLComponents(string:"https://localhost/?" + value), let items = parts.queryItems,
              items.filter({ $0.name == "method" }).count == 1,
              items.first(where: { $0.name == "method" })?.value == "alipay.trade.app.pay",
              items.filter({ $0.name == "biz_content" }).count == 1,
              let content = items.first(where: { $0.name == "biz_content" })?.value,
              let data = content.data(using:.utf8),
              let body = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              let amountString = body["total_amount"] as? String,
              amountString.range(of:#"^[0-9]+(?:\.[0-9]{1,2})?$"#,options:.regularExpression) != nil,
              let amount = Decimal(string:amountString,locale:Locale(identifier:"en_US_POSIX")),
              amount > 0, amount <= maximum else { return false }
        return true
    }
}

/// Accept only observed Alipay checkout forms, preserving backend-issued parameters.
/// No guessed payment URL fields or caller-supplied arbitrary web addresses.
private enum PaymentJSON: Decodable {
    case string(String), object([String:PaymentJSON]), array([PaymentJSON]), other
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String:PaymentJSON].self) { self = .object(value) }
        else if let value = try? c.decode([PaymentJSON].self) { self = .array(value) }
        else { self = .other }
    }
    var alipayURL: URL? {
        switch self {
        case .string(let text):
            guard let url = URL(string:text), LaundryPayment.isAllowedCheckoutURL(url) else { return nil }
            return url
        case .object(let items): return items.sorted { $0.key < $1.key }.compactMap { $0.value.alipayURL }.first
        case .array(let items): return items.compactMap(\.alipayURL).first
        case .other: return nil
        }
    }
}

public protocol LaundryOrdering: Sendable {
    func create(config: LaundryConfig, snapshot: LaundrySnapshot, program: LaundryProgram) async throws -> LaundryCreatedOrder
    func order(config: LaundryConfig, id: String) async throws -> LaundryOrder
    func payment(config: LaundryConfig, id: String) async throws -> LaundryPayment
    func cancel(config: LaundryConfig, id: String) async throws
    func preparePayment(config: LaundryConfig, id: String) async
}

extension LaundryOrdering {
    public func preparePayment(config: LaundryConfig, id: String) async {}
}

struct LaundryPaymentMethods: Decodable, Sendable {
    struct Channel: Decodable, Sendable {
        let channel: String
        let branchType: Int?
        func argumentsPath(orderID: String) throws -> String {
            guard LaundryProvider.validOrderId(orderID), ["alipay","alipayF2F"].contains(channel) else { throw LaundryError.response }
            var parts = URLComponents()
            parts.path = "/api/v1/payment/arguments"
            parts.queryItems = [URLQueryItem(name:"channel",value:channel),URLQueryItem(name:"orderId",value:orderID),URLQueryItem(name:"payVersion",value:"1")]
            if let branchType { parts.queryItems?.append(URLQueryItem(name:"branchType",value:String(branchType))) }
            // Current official washer cashier's “立即支付” action, distinct from its promotional action.
            if channel == "alipayF2F" { parts.queryItems?.append(URLQueryItem(name:"alipayF2FNoAds",value:"true")) }
            guard let path = parts.string else { throw LaundryError.response }
            return path
        }
    }
    let channels: [Channel]
    var preferred: Channel? { channels.first { $0.channel == "alipay" } ?? channels.first { $0.channel == "alipayF2F" } }
}

/// Only read-only channel metadata is shared, never payment arguments or checkout links.
actor LaundryPaymentMethodsCache {
    private struct Entry {
        let token: UUID
        let config: LaundryConfig
        let orderID: String
        let expiresAt: Date
        let task: Task<LaundryPaymentMethods, Error>
    }
    private var entry: Entry?
    func value(config: LaundryConfig, id: String, now: Date = Date(),
               load: @escaping @Sendable () async throws -> LaundryPaymentMethods) async throws -> LaundryPaymentMethods {
        let current: Entry
        if let entry, entry.orderID == id, entry.config.deviceId == config.deviceId,
           entry.config.headers == config.headers, entry.config.qrCode == config.qrCode, now < entry.expiresAt {
            current = entry
        } else {
            current = Entry(token:UUID(),config:config,orderID:id,expiresAt:now.addingTimeInterval(45),task:Task { try await load() })
            entry = current
        }
        do { return try await current.task.value }
        catch {
            if entry?.token == current.token { entry = nil }
            throw error
        }
    }
}

private struct LaundryCancelAck: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

extension LaundryProvider: LaundryOrdering {
    public func create(config: LaundryConfig, snapshot: LaundrySnapshot, program: LaundryProgram) async throws -> LaundryCreatedOrder {
        guard snapshot.deviceId == config.deviceId, snapshot.moduleType == 7,
              snapshot.createOrderEnabled, snapshot.status == 0,
              snapshot.activeOrderId == nil, snapshot.programs.contains(where: { $0.id == program.id }),
              Date().timeIntervalSince(snapshot.fetchedAt) < 60,
              let store = snapshot.storeId, !store.isEmpty, let type = snapshot.deviceTypeId else { throw LaundryError.response }
        let body = try JSONSerialization.data(withJSONObject:["type":1,"deviceTypeId":type,"deviceId":config.deviceId,
            "deviceWashModelId":program.id,"storeId":store,"additionParams":[String:String]()])
        return try await request("/api/v1/orders/create",config:config,method:"POST",body:body)
    }
    public func order(config: LaundryConfig, id: String) async throws -> LaundryOrder {
        guard Self.validOrderId(id) else { throw LaundryError.response }
        return try await request("/api/v1/orders/\(id)/detail?additional=price",config:config)
    }
    public func payment(config: LaundryConfig, id: String) async throws -> LaundryPayment {
        guard Self.validOrderId(id) else { throw LaundryError.response }
        let methods = try await paymentMethods(config:config,id:id)
        guard let channel = methods.preferred else { throw LaundryError.response }
        // Do not opt into a signed automatic-debit channel. Fetching arguments still requires explicit payment consent.
        return try await request(channel.argumentsPath(orderID:id),config:config)
    }
    private func paymentMethods(config: LaundryConfig, id: String) async throws -> LaundryPaymentMethods {
        try await paymentMethodsCache.value(config:config,id:id) { [self] in
            try await request("/api/v1/payment/methods?orderId=\(id)&include=alipay",config:config)
        }
    }
    public func preparePayment(config: LaundryConfig, id: String) async {
        guard Self.validOrderId(id) else { return }
        // Best effort: overlap channel lookup with order detail. No financial request here.
        Task { [self] in _ = try? await paymentMethods(config:config,id:id) }
    }
    public static func validOrderId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
    }
    public func cancel(config: LaundryConfig, id: String) async throws {
        guard Self.validOrderId(id) else { throw LaundryError.response }
        let body = try JSONSerialization.data(withJSONObject:["orderId":id])
        let _: LaundryCancelAck = try await request("/api/v1/orders/\(id)/cancel",config:config,
            method:"POST",body:body,emptyValue:LaundryCancelAck())
    }
}

public enum LaundryCheckoutStage: String, Codable, Sendable { case creating, created, paymentRequested, cancellationRequested, completed }
public struct LaundryCheckoutRecord: Codable, Sendable {
    public let deviceId: String
    public let programId: Int
    public let programName: String
    public let expectedPrice: Decimal
    public let createdAt: Date
    public var stage: LaundryCheckoutStage
    public var orderId: String?
    public var order: LaundryOrder?
    public var orderUpdatedAt: Date? = nil
    public var credentialIdentity: String? = nil
    public func belongs(to config: LaundryConfig) -> Bool {
        deviceId == config.deviceId && (credentialIdentity == nil || credentialIdentity == config.credentialIdentity)
    }
}
@MainActor public protocol LaundryCheckoutStore {
    func load() throws -> LaundryCheckoutRecord?
    func save(_ value: LaundryCheckoutRecord) throws
}
public enum LaundryCheckoutError: String, Error, LocalizedError {
    case pending = "已有待核对订单，请先刷新订单或在U净核对"
    case changed = "设备或价格已变化，请刷新后重新确认"
    case uncertain = "结果尚未确认，请刷新订单，勿重复下单或付款"
    case checkoutUnavailable = "暂时无法打开支付宝，请保留订单并核对付款状态"
    public var errorDescription: String? { rawValue }
}

@MainActor public final class LaundryCheckoutController {
    public private(set) var record: LaundryCheckoutRecord?
    private var busy = false
    private let store: any LaundryCheckoutStore
    private let api: any LaundryOrdering
    public init(store: any LaundryCheckoutStore, api: any LaundryOrdering) throws {
        self.store = store; self.api = api; record = try store.load()
    }
    public func associateLegacyAccount(config: LaundryConfig) throws {
        guard !busy, var next = record, next.credentialIdentity == nil, next.deviceId == config.deviceId else { return }
        next.credentialIdentity = config.credentialIdentity
        try store.save(next); record = next
    }
    public func migrateCompletedAccount(from old: LaundryConfig, to new: LaundryConfig) throws {
        guard !busy, var next = record, next.stage == .completed, next.belongs(to:old), old.deviceId == new.deviceId else { return }
        next.credentialIdentity = new.credentialIdentity
        try store.save(next); record = next
    }
    public func create(config: LaundryConfig, snapshot: LaundrySnapshot, program: LaundryProgram) async throws {
        guard !busy, record == nil || record?.stage == .completed else { throw LaundryCheckoutError.pending }
        guard snapshot.deviceId == config.deviceId, snapshot.moduleType == 7,
              snapshot.status == 0, snapshot.createOrderEnabled, snapshot.activeOrderId == nil,
              Date().timeIntervalSince(snapshot.fetchedAt) >= 0, Date().timeIntervalSince(snapshot.fetchedAt) < 60,
              snapshot.programs.contains(where: { $0.id == program.id && $0.price == program.price }) else { throw LaundryCheckoutError.changed }
        busy = true; defer { busy = false }
        var next = LaundryCheckoutRecord(deviceId:config.deviceId,programId:program.id,programName:program.workModelName,
            expectedPrice:program.price,createdAt:Date(),stage:.creating)
        next.credentialIdentity = config.credentialIdentity
        try store.save(next); record = next
        // A timeout/crash leaves 'creating' durable. Never automatically retry creation.
        let receipt = try await api.create(config:config,snapshot:snapshot,program:program)
        guard LaundryProvider.validOrderId(receipt.id) else { throw LaundryCheckoutError.uncertain }
        next.orderId = receipt.id
        try store.save(next); record = next
        await api.preparePayment(config:config,id:receipt.id)
        // Preserve the ID before fetching detail, even if that read fails.
        let order = try await api.order(config:config,id:receipt.id)
        guard order.deviceId == config.deviceId, order.id == receipt.id,
              order.deviceWashModelId == next.programId else { throw LaundryCheckoutError.uncertain }
        next.order = order; next.orderUpdatedAt = Date(); next.stage = order.terminal ? .completed : .created
        try store.save(next); record = next
    }
    public func payment(config: LaundryConfig) async throws -> LaundryPayment {
        guard !busy, var next = record, next.belongs(to:config),
              next.stage == .created, let id = next.orderId,
              let order = next.order, ["10","17"].contains(order.status.text), order.payFlag?.text == "0" else { throw LaundryCheckoutError.pending }
        guard let amount = order.payPrice, amount >= 0, amount <= next.expectedPrice else { throw LaundryCheckoutError.changed }
        busy = true; defer { busy = false }
        // Arguments can have financial side effects; consent precedes this durable marker.
        next.stage = .paymentRequested; try store.save(next); record = next
        return try await api.payment(config:config,id:id)
    }
    public func refresh(config: LaundryConfig) async throws {
        guard !busy, var next = record, next.belongs(to:config), let id = next.orderId else { throw LaundryCheckoutError.uncertain }
        busy = true; defer { busy = false }
        let order = try await api.order(config:config,id:id)
        guard order.id == id, order.deviceId == next.deviceId,
              order.deviceWashModelId == next.programId else { throw LaundryCheckoutError.uncertain }
        next.order = order; next.orderUpdatedAt = Date()
        if order.terminal { next.stage = .completed }
        else if next.stage == .creating { next.stage = .created }
        try store.save(next); record = next
    }
    public func recover(config: LaundryConfig, candidateOrderId: String) async throws {
        guard !busy, var next = record, next.stage == .creating,
              next.belongs(to:config), next.orderId == nil,
              LaundryProvider.validOrderId(candidateOrderId) else { throw LaundryCheckoutError.pending }
        busy = true; defer { busy = false }
        let order = try await api.order(config:config,id:candidateOrderId)
        let formatter = ISO8601DateFormatter()
        guard order.id == candidateOrderId, order.deviceId == next.deviceId,
              order.deviceWashModelId == next.programId,
              let rawDate = order.createAt, let date = formatter.date(from:rawDate),
              abs(date.timeIntervalSince(next.createdAt)) < 120,
              let price = order.payPrice, price >= 0, price <= next.expectedPrice else { throw LaundryCheckoutError.uncertain }
        next.orderId = order.id; next.order = order; next.orderUpdatedAt = Date(); next.stage = order.terminal ? .completed : .created
        try store.save(next); record = next
    }
    public func cancel(config: LaundryConfig) async throws {
        guard !busy, var next = record, [.created,.paymentRequested].contains(next.stage),
              next.belongs(to:config), let id = next.orderId else { throw LaundryCheckoutError.pending }
        busy = true; defer { busy = false }
        let fresh = try await api.order(config:config,id:id)
        guard fresh.id == id, fresh.deviceId == next.deviceId,
              fresh.deviceWashModelId == next.programId else { throw LaundryCheckoutError.uncertain }
        next.order = fresh; next.orderUpdatedAt = Date()
        if fresh.terminal {
            next.stage = .completed; try store.save(next); record = next; return
        }
        try store.save(next); record = next
        guard ["10","17"].contains(fresh.status.text), fresh.payFlag?.text == "0" else { throw LaundryCheckoutError.pending }
        next.stage = .cancellationRequested
        try store.save(next); record = next
        // POST once. Even a timeout is followed only by a read, never another cancellation.
        do { try await api.cancel(config:config,id:id) } catch { /* Verify server state below. */ }
        let final = try await api.order(config:config,id:id)
        guard final.id == id, final.deviceId == next.deviceId,
              final.deviceWashModelId == next.programId else { throw LaundryCheckoutError.uncertain }
        next.order = final; next.orderUpdatedAt = Date()
        if final.terminal { next.stage = .completed }
        try store.save(next); record = next
        guard final.terminal else { throw LaundryCheckoutError.uncertain }
    }
}
