import Foundation

// U净 laundry models (architecture §2.3, A.5). Values only; the client decodes them, the
// checkout reducer (`LaundryCheckout.swift`) drives orders and payment.

// MARK: - Account

/// A U净 login (Keychain `laundry.account`). `id` is U净's app user id (`data.id`, the JWT
/// `appUserId`), `userId` its business user id; both are decimal strings.
public struct UjingAccount: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public var id: String
    public var userId: String
    public var token: String
    public init(id: String, userId: String, token: String) { self.id = id; self.userId = userId; self.token = token }
    public var description: String { "UjingAccount(<redacted>)" }
    public var debugDescription: String { description }
}

/// What `laundry.account` holds: the per-install `x-mobile-id` (kept across logins) and the
/// current login, if any.
public struct UjingAccountItem: Sendable, Equatable, Codable, CustomStringConvertible {
    public var mobileID: String
    public var account: UjingAccount?
    public init(mobileID: String, account: UjingAccount? = nil) { self.mobileID = mobileID; self.account = account }
    public var description: String { "UjingAccountItem(signedIn: \(account != nil))" }
}

public enum UjingInput {
    /// 11-digit mainland mobile number starting with 1.
    public static func isMobile(_ s: String) -> Bool { s.range(of: "^1[0-9]{10}$", options: .regularExpression) != nil }
    /// 4–8 digit SMS code.
    public static func isSMSCode(_ s: String) -> Bool { s.range(of: "^[0-9]{4,8}$", options: .regularExpression) != nil }
    /// Order ids are ASCII letters/digits, at most 80 characters (they go into URL paths).
    public static func isOrderID(_ s: String) -> Bool { s.range(of: "^[A-Za-z0-9]{1,80}$", options: .regularExpression) != nil }

    /// The machine label QR: `https://q.ujing.com.cn/ucqrc/index.html?cd=<18 digits>`, nothing else.
    public static func isWasherQR(_ text: String) -> Bool {
        guard text.utf8.count <= 2048, let url = URLComponents(string: text), url.scheme == "https",
              url.host == "q.ujing.com.cn", url.path == "/ucqrc/index.html", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil else { return false }
        let codes = (url.queryItems ?? []).filter { $0.name == "cd" }
        guard codes.count == 1, let code = codes[0].value else { return false }
        return code.range(of: "^[0-9]{18}$", options: .regularExpression) != nil
    }
}

// MARK: - Machines

/// One wash program (`deviceWashModel[]`). `price` is what U净 charges (promotion price when
/// `isPromotion == 1`, else base price; both in fen).
public struct WasherProgram: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: Int
    public var name: String
    public var minutes: Int
    public var price: Money
    public init(id: Int, name: String, minutes: Int, price: Money) {
        self.id = id; self.name = name; self.minutes = minutes; self.price = price
    }
}

/// `devices/scanWasherCode` → `data.result`.
public struct WasherScan: Sendable, Equatable, Codable {
    public var deviceID: String
    public var moduleType: Int
    /// 0 idle, 1 washing, 2 fault, 7 not opened, 8 offline, 9 disabled, 11 reserved.
    public var status: Int
    public var createOrderEnabled: Bool
    /// The account's unfinished order on this machine (`""`, `"0"` and missing mean none).
    public var activeOrderID: String?
    public init(deviceID: String, moduleType: Int, status: Int, createOrderEnabled: Bool, activeOrderID: String?) {
        self.deviceID = deviceID; self.moduleType = moduleType; self.status = status
        self.createOrderEnabled = createOrderEnabled; self.activeOrderID = activeOrderID
    }
}

/// `app/washer/devices/program/info` → `data` (visible programs only).
public struct WasherInfo: Sendable, Equatable, Codable {
    public var deviceID: String
    public var deviceNo: String
    public var typeName: String
    public var storeName: String
    public var storeID: String?
    public var deviceTypeID: Int?
    public var moduleType: Int
    public var programs: [WasherProgram]
    public init(deviceID: String, deviceNo: String, typeName: String, storeName: String, storeID: String?,
                deviceTypeID: Int?, moduleType: Int, programs: [WasherProgram]) {
        self.deviceID = deviceID; self.deviceNo = deviceNo; self.typeName = typeName; self.storeName = storeName
        self.storeID = storeID; self.deviceTypeID = deviceTypeID; self.moduleType = moduleType; self.programs = programs
    }
}

/// Scan + program info of one machine, read together.
public struct WasherSnapshot: Sendable, Equatable, Codable {
    public var qrCode: String
    public var scan: WasherScan
    public var info: WasherInfo
    public var fetchedAt: Date
    public init(qrCode: String, scan: WasherScan, info: WasherInfo, fetchedAt: Date) {
        self.qrCode = qrCode; self.scan = scan; self.info = info; self.fetchedAt = fetchedAt
    }

    public var deviceID: String { scan.deviceID }

    /// Only module type 7 (the one the existing app has used end to end) is ordered from the app.
    public static let orderableModuleType = 7
    /// A snapshot older than this is re-read before an order is created.
    public static let maxOrderAge: TimeInterval = 60

    /// Free, orderable, no unfinished order, and the fields `orders/create` needs are present.
    public var isOrderable: Bool {
        scan.status == 0 && scan.createOrderEnabled && scan.activeOrderID == nil
            && scan.moduleType == Self.orderableModuleType && info.moduleType == scan.moduleType
            && info.storeID?.isEmpty == false && info.deviceTypeID != nil
    }

    public var stateLabel: String {
        switch scan.status {
        case 1: return "洗衣中"
        case 11: return "已被预约"
        case 2: return "设备故障"
        case 8: return "设备离线"
        case 7: return "尚未开通"
        case 9: return "设备停用"
        default: break
        }
        if scan.activeOrderID != nil { return "已有订单" }
        return scan.status == 0 && scan.createOrderEnabled ? "空闲" : "暂不可用"
    }
}

// MARK: - Orders

/// `orders/create` body fields.
public struct OrderRequest: Sendable, Equatable, Codable {
    public var deviceID: String
    public var deviceTypeID: Int
    public var storeID: String
    public var programID: Int
    public init(deviceID: String, deviceTypeID: Int, storeID: String, programID: Int) {
        self.deviceID = deviceID; self.deviceTypeID = deviceTypeID; self.storeID = storeID; self.programID = programID
    }
}

/// U净 order status code (kept as text: the server sends numbers or strings).
public struct LaundryOrderStatus: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public var code: String
    public init(_ code: String) { self.code = code }
    public var description: String { code }

    /// 10 reserved/unpaid, 17 unpaid.
    public var isAwaitingPayment: Bool { code == "10" || code == "17" }
    /// 50 done, 51 payment timed out, 52 machine didn't start, 53 cancelled.
    public var isTerminal: Bool { ["50", "51", "52", "53"].contains(code) }
    /// Starting / washing (existing app's list).
    public var isRunning: Bool { ["21", "22", "24", "29", "30", "35", "40"].contains(code) }
    public var isWashing: Bool { code == "40" }
    public var isDone: Bool { code == "50" }
    public var isFailedStart: Bool { code == "52" }

    public var label: String {
        switch code {
        case "10": return "已预约 · 待付款"
        case "17": return "待付款"
        case "20": return "已付款，等待启动"
        case "21": return "正在启动"
        case "40": return "洗衣中"
        case "50": return "洗衣完成"
        case "51": return "付款已超时"
        case "52": return "机器没启动。去 U净 的订单里看看有没有扣款。"
        case "53": return "订单已取消"
        default: return "订单状态待核对"
        }
    }
}

/// `orders/{id}/detail?additional=price` → `data`.
public struct LaundryOrder: Sendable, Equatable, Codable {
    public var id: String
    public var deviceID: String
    public var status: LaundryOrderStatus
    /// `payFlag` 1 = paid, 0 = unpaid, nil = not sent.
    public var paid: Bool?
    public var statusRemark: String?
    /// Seconds left while washing.
    public var remainSeconds: Int?
    public var programID: Int?
    /// ISO 8601 text as sent (`createAt`).
    public var createdAt: String?
    /// `payPrice` (yuan in the reply), the amount payment must match.
    public var price: Money?
    /// Seconds until an unpaid reservation is cancelled by U净 (`countDown`).
    public var countDown: Int?

    public init(id: String, deviceID: String, status: LaundryOrderStatus, paid: Bool? = nil, statusRemark: String? = nil,
                remainSeconds: Int? = nil, programID: Int? = nil, createdAt: String? = nil, price: Money? = nil, countDown: Int? = nil) {
        self.id = id; self.deviceID = deviceID; self.status = status; self.paid = paid; self.statusRemark = statusRemark
        self.remainSeconds = remainSeconds; self.programID = programID; self.createdAt = createdAt; self.price = price
        self.countDown = countDown
    }

    /// Unpaid and still payable/cancellable (10/17 and not flagged paid).
    public var isUnpaid: Bool { status.isAwaitingPayment && paid != true }
}

// MARK: - Payment

/// `payment/methods` → `data.channels[]`. Only `alipay` and `alipayF2F` are used.
public struct PayChannel: Sendable, Equatable, Hashable, Codable {
    public var channel: String
    public var branchType: Int?
    public init(channel: String, branchType: Int? = nil) { self.channel = channel; self.branchType = branchType }

    public static let supported: [String] = ["alipay", "alipayF2F"]

    /// `alipay` first, then `alipayF2F` (the existing app's order); never an automatic-debit channel.
    public static func preferred(_ channels: [PayChannel]) -> PayChannel? {
        channels.first { $0.channel == "alipay" } ?? channels.first { $0.channel == "alipayF2F" }
    }
}

/// `payment/arguments` → `data`, kept raw until `PaymentLaunchPolicy` has checked it. Never
/// persisted, logged or replayed.
public struct PaymentArguments: Sendable, Equatable, CustomStringConvertible {
    public var data: JSONValue
    public init(_ data: JSONValue) { self.data = data }
    public var description: String { "PaymentArguments(<redacted>)" }
}

/// What the app may do with checked payment arguments.
public enum PayLaunch: Sendable, Equatable, CustomStringConvertible {
    /// `skipPay` / `jumpToQuery`: nothing to open; read the order.
    case query
    /// Open this URL in the Alipay app (no return URL: poll the order afterwards).
    case checkout(URL)
    /// Hand this signed `alipay.trade.app.pay` order string to AlipaySDK.
    case sdk(String)
    public var description: String {
        switch self {
        case .query: return "PayLaunch.query"
        case .checkout: return "PayLaunch.checkout(<redacted>)"
        case .sdk: return "PayLaunch.sdk(<redacted>)"
        }
    }
}

public enum PaymentLaunchRefusal: String, Error, Sendable, Codable, Equatable {
    /// A link whose scheme/host/shape is not on the allow-list.
    case disallowedLink
    /// The amount in the link or signed order differs from the order amount.
    case amountMismatch
    /// The order amount is unknown, so nothing can be checked.
    case unknownAmount
    /// Nothing usable in the reply.
    case unavailable
}

/// Payment-launch validation (architecture §3.2). Allow-list:
/// - `https://qr.alipay.com/<code>` checkout pages;
/// - the U净 Alipay F2F link `alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url=<https://openauth.alipay.com/oauth2/publicAppAuthorize.htm?…redirect_uri=https://wx.zhinengxiyifang.cn/static/commonWasher/index.html…>`;
/// - a signed `alipay.trade.app.pay` order string for AlipaySDK.
/// Any amount carried by the link (`total_amount`/`totalAmount`/`amount`, also inside nested
/// URLs) or by the signed order (`biz_content.total_amount`) must equal the order amount.
public enum PaymentLaunchPolicy {
    public static let checkoutHost = "qr.alipay.com"
    public static let authHost = "openauth.alipay.com"
    public static let authPath = "/oauth2/publicAppAuthorize.htm"
    /// U净's own pay-return page (from the existing app's observed F2F link).
    public static let returnHost = "wx.zhinengxiyifang.cn"
    public static let returnPath = "/static/commonWasher/index.html"
    static let amountKeys: Set<String> = ["total_amount", "totalamount", "amount"]

    public static func launch(for arguments: PaymentArguments, orderAmount: Money?) throws -> PayLaunch {
        let data = arguments.data
        if flag(data["skipPay"]) == true || flag(data["jumpToQuery"]) == true { return .query }
        guard let orderAmount, orderAmount.fen > 0 else { throw PaymentLaunchRefusal.unknownAmount }

        var strings: [String] = []
        collectStrings(data, into: &strings)
        var sawLink = false
        for text in strings {
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { continue }
            if ["alipays", "alipay", "weixin", "http", "https"].contains(scheme) { sawLink = true }
            guard isAllowedCheckoutURL(url) else { continue }
            guard linkAmountsMatch(url, orderAmount) else { throw PaymentLaunchRefusal.amountMismatch }
            return .checkout(url)
        }
        let signed = [data["payInfo"]?["orderInfo"]?.text, data["orderInfo"]?.text]
            .compactMap { $0 }.first { !$0.isEmpty && URL(string: $0)?.scheme == nil }
        if let signed {
            guard let amount = signedOrderAmount(signed) else { throw PaymentLaunchRefusal.unavailable }
            guard amount == orderAmount else { throw PaymentLaunchRefusal.amountMismatch }
            return .sdk(signed)
        }
        throw sawLink ? PaymentLaunchRefusal.disallowedLink : PaymentLaunchRefusal.unavailable
    }

    /// The final gate the app runs right before opening a URL.
    public static func isAllowedCheckoutURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else { return false }
        if parts.scheme == "https", parts.host == checkoutHost, parts.path.count > 1 { return true }
        guard parts.scheme == "alipays", parts.host == "platformapi", parts.path == "/startApp",
              let items = parts.queryItems, Set(items.map(\.name)).count == items.count else { return false }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard values["appId"] == "20000042", values["actionType"] == "WebView", values["followType"] == "PUBLIC",
              let nested = values["url"], let auth = URLComponents(string: nested),
              auth.scheme == "https", auth.host == authHost, auth.path == authPath,
              auth.user == nil, auth.password == nil, auth.port == nil, auth.fragment == nil,
              let query = auth.queryItems, Set(query.map(\.name)).count == query.count,
              let redirect = query.first(where: { $0.name == "redirect_uri" })?.value,
              let target = URLComponents(string: redirect), target.scheme == "https", target.host == returnHost,
              target.path == returnPath, target.user == nil, target.password == nil,
              target.port == nil, target.fragment == nil else { return false }
        return true
    }

    /// Every amount parameter in the link and its nested URLs equals `amount`.
    static func linkAmountsMatch(_ url: URL, _ amount: Money, depth: Int = 0) -> Bool {
        guard depth < 4, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return true }
        for item in items {
            let value = item.value ?? ""
            if amountKeys.contains(item.name.lowercased()) {
                guard let found = strictYuan(value), found == amount else { return false }
            }
            if let nested = URL(string: value), nested.scheme != nil, !linkAmountsMatch(nested, amount, depth: depth + 1) {
                return false
            }
        }
        return true
    }

    /// `biz_content.total_amount` of a signed `alipay.trade.app.pay` string (single `method` and
    /// `biz_content`), or nil when it is not such a string.
    public static func signedOrderAmount(_ value: String) -> Money? {
        guard value.utf8.count <= 16 * 1024,
              let parts = URLComponents(string: "https://localhost/?" + value), let items = parts.queryItems,
              items.filter({ $0.name == "method" }).count == 1,
              items.first(where: { $0.name == "method" })?.value == "alipay.trade.app.pay",
              items.filter({ $0.name == "biz_content" }).count == 1,
              let content = items.first(where: { $0.name == "biz_content" })?.value,
              let body = try? JSONValue.parse(content), case .string(let text)? = body["total_amount"] else { return nil }
        return strictYuan(text)
    }

    static func strictYuan(_ text: String) -> Money? {
        guard text.range(of: #"^[0-9]+(\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        return Money(yuanString: text)
    }

    static func flag(_ v: JSONValue?) -> Bool? {
        switch v {
        case .bool(let b)?: return b
        case .int(let i)? where i == 0 || i == 1: return i == 1
        case .string(let s)? where ["0", "1", "true", "false"].contains(s): return s == "1" || s == "true"
        default: return nil
        }
    }

    /// Strings in key-sorted order (deterministic choice when several links are present).
    static func collectStrings(_ v: JSONValue, into out: inout [String], depth: Int = 0) {
        guard depth < 8 else { return }
        switch v {
        case .string(let s): out.append(s)
        case .object(let o): for k in o.keys.sorted() { collectStrings(o[k]!, into: &out, depth: depth + 1) }
        case .array(let a): for x in a { collectStrings(x, into: &out, depth: depth + 1) }
        default: break
        }
    }
}
