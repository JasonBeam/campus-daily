import Foundation

/// The U净 calls `LaundryEngine` needs (implemented by `UjingClient`, faked in tests).
/// Errors are `ServiceError`. For the state-changing calls (`createOrder`,
/// `paymentArguments`, `cancel`) anything that is not a definite answer is `uncertain(.ujing)`.
public protocol LaundryOrdering: Sendable {
    func scan(qr: String) async throws -> WasherScan
    func createOrder(_ request: OrderRequest) async throws -> String
    func order(_ id: String) async throws -> LaundryOrder
    func paymentMethods(_ id: String) async throws -> [PayChannel]
    func paymentArguments(_ id: String, channel: PayChannel) async throws -> PaymentArguments
    func cancel(_ id: String) async throws
}

public enum UjingEndpoints {
    public static let base = "https://phoenix.ujing.online"
    public static let captcha = "/api/v1/captcha"
    public static let login = "/api/v1/login"
    public static let scan = "/api/v1/devices/scanWasherCode"
    public static let programs = "/api/v1/app/washer/devices/program/info"
    public static let create = "/api/v1/orders/create"
    public static let methods = "/api/v1/payment/methods"
    public static let arguments = "/api/v1/payment/arguments"
    public static func detail(_ id: String) -> String { "/api/v1/orders/\(id)/detail" }
    public static func cancel(_ id: String) -> String { "/api/v1/orders/\(id)/cancel" }

    /// `x-app-code` as the existing iOS and Android clients send it: `ZI` on the SMS
    /// captcha/login calls, `BI` on every authenticated call.
    public static let loginAppCode = "ZI"
    public static let appCode = "BI"
    public static let appVersion = "2.4.18"
    public static let maxPrograms = 50
}

/// Per-install client identity: `x-mobile-id` (UUID kept in `laundry.account`), brand and UA.
public struct UjingDevice: Sendable, Equatable {
    public var mobileID: String
    public var userAgent: String
    public var brand: String
    public init(mobileID: String, userAgent: String, brand: String = "apple") {
        self.mobileID = mobileID; self.userAgent = userAgent; self.brand = brand
    }
}

/// phoenix.ujing.online. Envelope `{code, message, data}`; HTTP 401 (or envelope 401/403) →
/// `sessionExpired(.ujing)` with no silent refresh; `code != 0` → `rejected(code, message)`.
public struct UjingClient: LaundryOrdering {
    let http: HTTPClient
    let device: UjingDevice
    let token: String?

    /// `token` nil = only the SMS login calls work (others fail with `sessionExpired` locally).
    public init(http: HTTPClient, device: UjingDevice, token: String? = nil) {
        self.http = http; self.device = device; self.token = token
    }

    public init(http: HTTPClient, device: UjingDevice, account: UjingAccount) {
        self.init(http: http, device: device, token: account.token)
    }

    // MARK: Login

    /// Sends an SMS code (`GET /api/v1/captcha?mobile&type=1`). Never called automatically;
    /// a lost reply is `uncertain` (don't ask again right away).
    public func requestSMS(mobile: String) async throws {
        guard UjingInput.isMobile(mobile) else { throw ServiceError.badRequest(.ujing) }
        var c = URLComponents(string: UjingEndpoints.base + UjingEndpoints.captcha)!
        c.queryItems = [URLQueryItem(name: "mobile", value: mobile), URLQueryItem(name: "type", value: "1")]
        let req = HTTPRequest(service: .ujing, method: .get, url: c.url!, headers: try loginHeaders(),
                              isStateChanging: true, logName: "captcha")
        _ = try Self.decode(try await http.send(req), stateChanging: true, login: true)
    }

    /// `POST /api/v1/login {mobile, captcha}` → account. A temporary token or a risk challenge
    /// is `rejected(.ujing, "verification", …)`: the user must verify in the U净 app first.
    public func login(mobile: String, code: String) async throws -> UjingAccount {
        guard UjingInput.isMobile(mobile), UjingInput.isSMSCode(code) else { throw ServiceError.badRequest(.ujing) }
        var headers = try loginHeaders()
        headers["Content-Type"] = "application/json"
        let body = try JSONValue.object(["mobile": .string(mobile), "captcha": .string(code)]).encoded()
        let req = HTTPRequest(service: .ujing, method: .post, url: URL(string: UjingEndpoints.base + UjingEndpoints.login)!,
                              headers: headers, body: body, logName: "login")
        let data = try Self.decode(try await http.send(req), stateChanging: false, login: true)
        return try Self.account(data)
    }

    public static let verificationMessage = "先在 U净 App 里验证一下，验证完再回来。"

    static func account(_ data: JSONValue?) throws -> UjingAccount {
        guard let data, data.object != nil else { throw ServiceError.malformed(.ujing, "data") }
        guard case .bool(let temporary)? = data["isTempToken"] else { throw ServiceError.malformed(.ujing, "data.isTempToken") }
        if temporary { throw ServiceError.rejected(.ujing, code: "verification", message: verificationMessage) }
        guard case .string(let token)? = data["token"], token.count > 20, token.count <= 4096,
              token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw ServiceError.malformed(.ujing, "data.token")
        }
        guard let id = numericID(data["id"]) else { throw ServiceError.malformed(.ujing, "data.id") }
        guard let userId = numericID(data["userId"]) else { throw ServiceError.malformed(.ujing, "data.userId") }
        return UjingAccount(id: id, userId: userId, token: token)
    }

    static func numericID(_ v: JSONValue?) -> String? {
        let text: String
        switch v {
        case .string(let s)?: text = s
        case .int(let i)?: text = String(i)
        default: return nil
        }
        return text.range(of: "^[0-9]{1,32}$", options: .regularExpression) != nil ? text : nil
    }

    // MARK: Machines (read-only)

    /// `POST devices/scanWasherCode {qrCode}` (read-only lookup of a machine label).
    public func scan(qr: String) async throws -> WasherScan {
        guard UjingInput.isWasherQR(qr) else { throw ServiceError.badRequest(.ujing) }
        let data = try await call(.post, UjingEndpoints.scan, json: ["qrCode": .string(qr)], name: "scanWasherCode")
        guard let r = data?["result"], r.object != nil else { throw ServiceError.malformed(.ujing, "data.result") }
        guard case .string(let id)? = r["deviceId"], !id.isEmpty, id.count <= 128 else { throw ServiceError.malformed(.ujing, "data.result.deviceId") }
        guard let module = r["moduleType"]?.intValue else { throw ServiceError.malformed(.ujing, "data.result.moduleType") }
        guard let status = r["status"]?.intValue else { throw ServiceError.malformed(.ujing, "data.result.status") }
        guard let enabled = Self.bool(r["createOrderEnabled"]) else { throw ServiceError.malformed(.ujing, "data.result.createOrderEnabled") }
        return WasherScan(deviceID: id, moduleType: module, status: status, createOrderEnabled: enabled,
                          activeOrderID: Self.normalizedOrderID(r["orderId"]))
    }

    /// `GET app/washer/devices/program/info?deviceId` (hidden programs dropped).
    public func programs(deviceID: String) async throws -> WasherInfo {
        guard !deviceID.isEmpty, deviceID.count <= 128 else { throw ServiceError.badRequest(.ujing) }
        let data = try await call(.get, UjingEndpoints.programs, query: [("deviceId", deviceID)], name: "programInfo")
        guard let d = data, d.object != nil else { throw ServiceError.malformed(.ujing, "data") }
        guard case .string(let id)? = d["deviceId"], id == deviceID else { throw ServiceError.malformed(.ujing, "data.deviceId") }
        guard let module = d["moduleType"]?.intValue else { throw ServiceError.malformed(.ujing, "data.moduleType") }
        guard let rows = d["deviceWashModel"]?.array, rows.count <= UjingEndpoints.maxPrograms else {
            throw ServiceError.malformed(.ujing, "data.deviceWashModel")
        }
        var programs: [WasherProgram] = []
        for (i, p) in rows.enumerated() {
            let path = "data.deviceWashModel[\(i)]"
            guard let pid = p["workModelId"]?.intValue else { throw ServiceError.malformed(.ujing, path + ".workModelId") }
            guard let name = p["workModelName"]?.text, !name.isEmpty else { throw ServiceError.malformed(.ujing, path + ".workModelName") }
            guard let minutes = p["time"]?.intValue, minutes > 0 else { throw ServiceError.malformed(.ujing, path + ".time") }
            guard let base = p["basePrice"]?.intValue, base >= 0 else { throw ServiceError.malformed(.ujing, path + ".basePrice") }
            let promo = p["isPromotion"]?.intValue == 1
            let promoPrice = p["promotionPrice"]?.intValue
            if promo, (promoPrice ?? -1) < 0 { throw ServiceError.malformed(.ujing, path + ".promotionPrice") }
            if (p["hide"]?.intValue ?? 0) != 0 { continue }
            programs.append(WasherProgram(id: pid, name: name, minutes: minutes, price: Money(fen: promo ? promoPrice! : base)))
        }
        guard Set(programs.map(\.id)).count == programs.count else { throw ServiceError.malformed(.ujing, "data.deviceWashModel.workModelId") }
        return WasherInfo(deviceID: id, deviceNo: d["deviceNo"]?.text ?? "", typeName: d["deviceTypeName"]?.text ?? "",
                          storeName: d["storeName"]?.text ?? "", storeID: d["storeId"]?.text.flatMap { $0.isEmpty ? nil : $0 },
                          deviceTypeID: d["deviceTypeId"]?.intValue, moduleType: module, programs: programs)
    }

    /// Scan + program info of one machine (machine status, store and price list).
    public func washer(qr: String, now: Date = Date()) async throws -> WasherSnapshot {
        let scan = try await scan(qr: qr)
        let info = try await programs(deviceID: scan.deviceID)
        guard info.moduleType == scan.moduleType else { throw ServiceError.malformed(.ujing, "data.moduleType") }
        return WasherSnapshot(qrCode: qr, scan: scan, info: info, fetchedAt: now)
    }

    // MARK: Orders

    /// `POST orders/create` (STATE). Returns the order id. Any unclear outcome is `uncertain`.
    public func createOrder(_ r: OrderRequest) async throws -> String {
        let data = try await call(.post, UjingEndpoints.create, json: [
            "type": .int(1), "deviceTypeId": .int(Int64(r.deviceTypeID)), "deviceId": .string(r.deviceID),
            "deviceWashModelId": .int(Int64(r.programID)), "storeId": .string(r.storeID), "additionParams": .object([:]),
        ], stateChanging: true, name: "createOrder")
        let id: String?
        if let d = data, d.object != nil { id = (d["orderId"] ?? d["id"])?.text } else { id = data?.text }
        guard let id, UjingInput.isOrderID(id) else { throw ServiceError.uncertain(.ujing) }
        return id
    }

    /// `GET orders/{id}/detail?additional=price`.
    public func order(_ id: String) async throws -> LaundryOrder {
        guard UjingInput.isOrderID(id) else { throw ServiceError.badRequest(.ujing) }
        let data = try await call(.get, UjingEndpoints.detail(id), query: [("additional", "price")], name: "orderDetail")
        return try Self.order(data)
    }

    static func order(_ data: JSONValue?) throws -> LaundryOrder {
        guard let d = data, d.object != nil else { throw ServiceError.malformed(.ujing, "data") }
        guard let id = d["orderId"]?.text, UjingInput.isOrderID(id) else { throw ServiceError.malformed(.ujing, "data.orderId") }
        guard case .string(let device)? = d["deviceId"], !device.isEmpty else { throw ServiceError.malformed(.ujing, "data.deviceId") }
        guard let status = d["status"]?.text, status.range(of: "^[0-9]{1,4}$", options: .regularExpression) != nil else {
            throw ServiceError.malformed(.ujing, "data.status")
        }
        var paid: Bool?
        if let flag = d["payFlag"], !flag.isNull {
            guard let t = flag.text, t == "0" || t == "1" else { throw ServiceError.malformed(.ujing, "data.payFlag") }
            paid = t == "1"
        }
        var price: Money?
        if let p = d["payPrice"], !p.isNull {
            switch p {
            case .int(let i): price = Money(fen: Int(i) * 100)
            case .double(let v): price = Money(yuanNumber: v)
            case .string(let s): price = Money(yuanString: s)
            default: price = nil
            }
            guard let value = price, value.fen >= 0 else { throw ServiceError.malformed(.ujing, "data.payPrice") }
        }
        return LaundryOrder(id: id, deviceID: device, status: LaundryOrderStatus(status), paid: paid,
                            statusRemark: d["statusRemark"]?.text, remainSeconds: d["remainTime"]?.intValue,
                            programID: d["deviceWashModelId"]?.intValue, createdAt: d["createAt"]?.text, price: price,
                            countDown: d["countDown"]?.intValue)
    }

    // MARK: Payment

    /// `GET payment/methods?orderId&include=alipay` (read-only).
    public func paymentMethods(_ id: String) async throws -> [PayChannel] {
        guard UjingInput.isOrderID(id) else { throw ServiceError.badRequest(.ujing) }
        let data = try await call(.get, UjingEndpoints.methods, query: [("orderId", id), ("include", "alipay")], name: "paymentMethods")
        guard let rows = data?["channels"]?.array else { throw ServiceError.malformed(.ujing, "data.channels") }
        return try rows.enumerated().map { i, row in
            guard case .string(let channel)? = row["channel"], !channel.isEmpty else { throw ServiceError.malformed(.ujing, "data.channels[\(i)].channel") }
            return PayChannel(channel: channel, branchType: row["branchType"]?.intValue)
        }
    }

    /// `GET payment/arguments` (MONEY: may register or skip a payment). Only after the user
    /// confirmed; the reply is checked by `PaymentLaunchPolicy` before anything opens.
    public func paymentArguments(_ id: String, channel: PayChannel) async throws -> PaymentArguments {
        guard UjingInput.isOrderID(id), PayChannel.supported.contains(channel.channel) else { throw ServiceError.badRequest(.ujing) }
        var query = [("channel", channel.channel), ("orderId", id), ("payVersion", "1")]
        if let b = channel.branchType { query.append(("branchType", String(b))) }
        // The official cashier's “立即支付” (no promotional detour).
        if channel.channel == "alipayF2F" { query.append(("alipayF2FNoAds", "true")) }
        let data = try await call(.get, UjingEndpoints.arguments, query: query, stateChanging: true, name: "paymentArguments")
        guard let data, data.object != nil else { throw ServiceError.uncertain(.ujing) }
        return PaymentArguments(data)
    }

    /// `POST orders/{id}/cancel {orderId}` (STATE).
    public func cancel(_ id: String) async throws {
        guard UjingInput.isOrderID(id) else { throw ServiceError.badRequest(.ujing) }
        _ = try await call(.post, UjingEndpoints.cancel(id), json: ["orderId": .string(id)], stateChanging: true, name: "cancelOrder")
    }

    // MARK: Plumbing

    func loginHeaders() throws -> [String: String] {
        try checkDevice()
        return ["x-app-code": UjingEndpoints.loginAppCode, "x-app-version": UjingEndpoints.appVersion,
                "x-mobile-id": device.mobileID, "x-mobile-brand": device.brand, "User-Agent": device.userAgent,
                "Accept": "application/json"]
    }

    func headers() throws -> [String: String] {
        try checkDevice()
        guard let token, !token.isEmpty, token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw ServiceError.sessionExpired(.ujing)
        }
        return ["Authorization": "Bearer " + token, "x-app-code": UjingEndpoints.appCode,
                "x-app-version": UjingEndpoints.appVersion, "x-mobile-id": device.mobileID,
                "x-mobile-brand": device.brand, "User-Agent": device.userAgent, "Accept": "application/json"]
    }

    func checkDevice() throws {
        guard UUID(uuidString: device.mobileID) != nil, device.userAgent.count <= 512,
              device.userAgent.rangeOfCharacter(from: .controlCharacters) == nil,
              device.brand.rangeOfCharacter(from: .controlCharacters) == nil else { throw ServiceError.badRequest(.ujing) }
    }

    private func call(_ method: HTTPMethod, _ path: String, query: [(String, String)] = [], json: [String: JSONValue]? = nil,
                      stateChanging: Bool = false, name: String) async throws -> JSONValue? {
        var c = URLComponents(string: UjingEndpoints.base + path)!
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = c.url else { throw ServiceError.badRequest(.ujing) }
        let h = try headers()
        let req: HTTPRequest
        if let json {
            req = .postJSON(service: .ujing, url: url, headers: h, json: json, bodyLimit: HTTPRequest.largeBodyLimit,
                            isStateChanging: stateChanging, logName: name)
        } else {
            req = HTTPRequest(service: .ujing, method: method, url: url, headers: h, bodyLimit: HTTPRequest.largeBodyLimit,
                              isStateChanging: stateChanging, logName: name)
        }
        return try Self.decode(try await http.send(req), stateChanging: stateChanging)
    }

    /// Envelope mapping. Returns `data` (nil when absent/null).
    static func decode(_ r: HTTPResponse, stateChanging: Bool, login: Bool = false) throws -> JSONValue? {
        if r.status == 401 || r.status == 403 { throw ServiceError.sessionExpired(.ujing) }
        guard (200..<300).contains(r.status) else {
            if stateChanging { throw ServiceError.uncertain(.ujing) }
            throw ServiceError.rejected(.ujing, code: "HTTP \(r.status)", message: "")
        }
        guard let root = try? JSONValue.parse(r.body), root.object != nil else {
            throw stateChanging ? ServiceError.uncertain(.ujing) : ServiceError.malformed(.ujing, "$")
        }
        guard let codeValue = root["code"], case .int(let code) = codeValue else {
            throw stateChanging ? ServiceError.uncertain(.ujing) : ServiceError.malformed(.ujing, "code")
        }
        if code == 401 || code == 403 { throw ServiceError.sessionExpired(.ujing) }
        guard code == 0 else {
            let message = ResponseDecoding.message(root)
            if login, isChallenge(message) {
                throw ServiceError.rejected(.ujing, code: "verification", message: verificationMessage)
            }
            throw ServiceError.rejection(.ujing, code: String(code), message: message)
        }
        guard let data = root["data"], !data.isNull else { return nil }
        return data
    }

    static func isChallenge(_ message: String) -> Bool {
        let m = message.lowercased()
        return ["滑块", "人机", "风控", "challenge", "captcha required"].contains { m.contains($0) }
    }

    static func bool(_ v: JSONValue?) -> Bool? {
        switch v {
        case .bool(let b)?: return b
        case .int(let i)? where i == 0 || i == 1: return i == 1
        default: return nil
        }
    }

    /// Missing, blank or `"0"` mean "no order".
    static func normalizedOrderID(_ v: JSONValue?) -> String? {
        guard let text = v?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text != "0" else { return nil }
        return text
    }
}
