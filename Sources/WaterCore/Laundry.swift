import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LaundryError: String, Error, LocalizedError {
    case configuration = "洗衣配置无效"
    case authentication = "U净登录已失效，请重新导入登录配置"
    case network = "暂时无法连接U净，保留上次查询"
    case response = "U净返回异常，暂时无法确认设备状态"
    public var errorDescription: String? { rawValue }
}

public enum WasherQRCode {
    public static func validate(_ text: String) throws {
        guard text.utf8.count <= 2048, let url = URLComponents(string:text), url.scheme == "https",
              url.host == "q.ujing.com.cn", url.path == "/ucqrc/index.html", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil else { throw LaundryError.configuration }
        let codes = (url.queryItems ?? []).filter { $0.name == "cd" }
        guard codes.count == 1, let code = codes[0].value, code.count == 18,
              code.utf8.allSatisfy({ (48...57).contains($0) }) else { throw LaundryError.configuration }
    }
}

public struct SavedWasher: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let qrCode: String
    public var name: String
    public let savedAt: Date
    public init(id: String, qrCode: String, name: String, savedAt: Date = Date()) {
        self.id = id; self.qrCode = qrCode; self.name = name; self.savedAt = savedAt
    }
}

public struct LaundryConfig: Codable, Sendable {
    public var headers: [String:String]
    public var qrCode: String
    public var deviceId: String
    public var accountID: String? = nil
    public init(headers: [String:String], qrCode: String, deviceId: String, accountID: String? = nil) {
        self.headers = headers; self.qrCode = qrCode; self.deviceId = deviceId
        self.accountID = accountID
    }
    public var credentialIdentity: String {
        let token = headers.first { $0.key.lowercased() == "authorization" }?.value ?? ""
        let identity = accountID.map { "account:" + $0 } ?? token
        return SHA256.hash(data:Data(identity.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    public func validate() throws {
        try WasherQRCode.validate(qrCode)
        if let accountID {
            guard !accountID.isEmpty, accountID.count <= 32, accountID.utf8.allSatisfy({ (48...57).contains($0) }) else { throw LaundryError.configuration }
        }
        guard !deviceId.isEmpty, deviceId.count <= 128,
              let qr = URLComponents(string: qrCode), qr.scheme == "https",
              qr.host == "q.ujing.com.cn", qr.path == "/ucqrc/index.html",
              headers.contains(where: { $0.key.lowercased() == "authorization" && $0.value.hasPrefix("Bearer ") && $0.value.count > 20 }),
              headers.allSatisfy({ !$0.value.contains("\r") && !$0.value.contains("\n") }) else { throw LaundryError.configuration }
    }
}

public struct LaundryProgram: Codable, Identifiable, Sendable {
    public let workModelId: Int
    public let workModelName: String
    public let time: Int
    public let basePrice: Int
    public let hide: Int
    public let isPromotion: Int
    public let promotionPrice: Int
    public var id: Int { workModelId }
    public var price: Decimal { Decimal(isPromotion == 1 ? promotionPrice : basePrice) / 100 }
}

public struct LaundrySnapshot: Codable, Sendable {
    public let deviceId: String
    public let deviceNo: String
    public let deviceTypeName: String
    public let storeName: String
    public let moduleType: Int
    public let status: Int
    public let createOrderEnabled: Bool
    public let programs: [LaundryProgram]
    public let fetchedAt: Date
    public var storeId: String? = nil
    public var deviceTypeId: Int? = nil
    public var activeOrderId: String? = nil
    public var stateLabel: String {
        if activeOrderId != nil { return status == 10 ? "已预约" : "已有订单" }
        return status == 0 && createOrderEnabled ? "空闲" : "暂不可用"
    }
}

private struct LaundryEnvelope<T: Decodable>: Decodable { let code: Int; let data: T? }
private struct LaundryScan: Decodable {
    struct Result: Decodable {
        let deviceId: String; let moduleType: Int; let status: Int; let createOrderEnabled: Bool
        let orderId: LaundryScalar?
    }
    let result: Result
}
private struct LaundryInfo: Decodable {
    let deviceId: String; let deviceNo: String; let deviceTypeName: String
    let storeName: String; let moduleType: Int; let deviceWashModel: [LaundryProgram]
    let storeId: String?; let deviceTypeId: Int?
}

private final class LaundryNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// U净 queries and explicitly confirmed order/payment requests. No BLE operations.
public final class LaundryProvider: @unchecked Sendable {
    private let session: URLSession
    let paymentMethodsCache = LaundryPaymentMethodsCache()
    private let responseObserver: (@Sendable (String, Int, Data) -> Void)?
    public init(responseObserver: (@Sendable (String, Int, Data) -> Void)? = nil) {
        self.responseObserver = responseObserver
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20; cfg.timeoutIntervalForResource = 30
        cfg.httpCookieStorage = nil; cfg.urlCache = nil
        session = URLSession(configuration:cfg,delegate:LaundryNoRedirect(),delegateQueue:nil)
    }
    func request<T: Decodable>(_ path: String, config: LaundryConfig,
        method: String = "GET", body: Data? = nil, emptyValue: T? = nil) async throws -> T {
        try await request(path,headers:config.headers,method:method,body:body,emptyValue:emptyValue)
    }
    private func request<T: Decodable>(_ path: String, headers: [String:String],
        method: String = "GET", body: Data? = nil, emptyValue: T? = nil) async throws -> T {
        var req = URLRequest(url:URL(string:"https://phoenix.ujing.online" + path)!)
        req.httpMethod = method; req.httpBody = body
        let allowed = Set(["authorization","x-app-code","x-app-version","weex-version","user-agent","content-type","x-mobile-id","x-mobile-brand"])
        for (key,value) in headers where allowed.contains(key.lowercased()) { req.setValue(value,forHTTPHeaderField:key) }
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let data: Data; let response: URLResponse
        do { (data,response) = try await session.data(for:req) }
        catch { throw LaundryError.network }
        guard let http = response as? HTTPURLResponse else { throw LaundryError.response }
        if path.hasPrefix("/api/v1/payment/arguments") || path == "/api/v1/orders/create" {
            responseObserver?(path,http.statusCode,data)
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw LaundryError.authentication }
        guard http.statusCode == 200, data.count < 1_048_576 else { throw LaundryError.response }
        guard let envelope = try? JSONDecoder().decode(LaundryEnvelope<T>.self,from:data) else { throw LaundryError.response }
        if envelope.code == 401 || envelope.code == 403 { throw LaundryError.authentication }
        guard envelope.code == 0, let value = envelope.data ?? emptyValue else { throw LaundryError.response }
        return value
    }
    public func query(config: LaundryConfig) async throws -> LaundrySnapshot {
        try config.validate()
        let body = try JSONSerialization.data(withJSONObject:["qrCode":config.qrCode])
        let scan: LaundryScan = try await request("/api/v1/devices/scanWasherCode",config:config,method:"POST",body:body)
        guard scan.result.deviceId == config.deviceId else { throw LaundryError.response }
        var parts = URLComponents(); parts.queryItems = [URLQueryItem(name:"deviceId",value:config.deviceId)]
        let info: LaundryInfo = try await request("/api/v1/app/washer/devices/program/info?" + (parts.percentEncodedQuery ?? ""),config:config)
        return try Self.snapshot(scan:scan,info:info,expected:config.deviceId)
    }
    /// Resolves a scanned label with the user's existing account. Does not bind or order.
    public func discover(config: LaundryConfig, qrCode: String) async throws -> (LaundryConfig, LaundrySnapshot) {
        try config.validate()
        return try await discover(headers:config.headers,accountID:config.accountID,qrCode:qrCode)
    }
    public func discover(headers: [String:String], accountID: String? = nil, qrCode: String) async throws -> (LaundryConfig, LaundrySnapshot) {
        try WasherQRCode.validate(qrCode)
        guard headers.contains(where:{ $0.key.lowercased() == "authorization" && $0.value.hasPrefix("Bearer ") && $0.value.count > 20 }),
              headers.values.allSatisfy({ $0.rangeOfCharacter(from:.controlCharacters) == nil }) else { throw LaundryError.authentication }
        let body = try JSONSerialization.data(withJSONObject:["qrCode":qrCode])
        let scan: LaundryScan = try await request("/api/v1/devices/scanWasherCode",headers:headers,method:"POST",body:body)
        guard !scan.result.deviceId.isEmpty, scan.result.moduleType == 7 else { throw LaundryError.response }
        let resolved = LaundryConfig(headers:headers,qrCode:qrCode,deviceId:scan.result.deviceId,accountID:accountID)
        try resolved.validate()
        var parts = URLComponents(); parts.queryItems = [URLQueryItem(name:"deviceId",value:resolved.deviceId)]
        let info: LaundryInfo = try await request("/api/v1/app/washer/devices/program/info?" + (parts.percentEncodedQuery ?? ""),config:resolved)
        return (resolved,try Self.snapshot(scan:scan,info:info,expected:resolved.deviceId))
    }
    public func activeOrderID(config: LaundryConfig) async throws -> String? {
        try config.validate()
        let body = try JSONSerialization.data(withJSONObject:["qrCode":config.qrCode])
        let scan: LaundryScan = try await request("/api/v1/devices/scanWasherCode",config:config,method:"POST",body:body)
        guard scan.result.deviceId == config.deviceId else { throw LaundryError.response }
        let id = scan.result.orderId?.text
        return id == "0" || id == "" ? nil : id
    }
    private static func snapshot(scan: LaundryScan, info: LaundryInfo, expected: String) throws -> LaundrySnapshot {
        guard info.deviceId == expected, scan.result.deviceId == expected,
              info.moduleType == scan.result.moduleType,
              info.deviceWashModel.allSatisfy({ $0.basePrice >= 0 && $0.promotionPrice >= 0 && $0.time > 0 }),
              Set(info.deviceWashModel.map(\.id)).count == info.deviceWashModel.count else { throw LaundryError.response }
        var value = LaundrySnapshot(deviceId:info.deviceId,deviceNo:info.deviceNo,deviceTypeName:info.deviceTypeName,
            storeName:info.storeName,moduleType:info.moduleType,status:scan.result.status,
            createOrderEnabled:scan.result.createOrderEnabled,programs:info.deviceWashModel.filter { $0.hide == 0 },fetchedAt:Date())
        value.storeId = info.storeId; value.deviceTypeId = info.deviceTypeId
        value.activeOrderId = scan.result.orderId?.text == "0" ? nil : scan.result.orderId?.text
        return value
    }
    public static func decodeEvidence(scanData: Data, infoData: Data, expectedDeviceId: String) throws -> LaundrySnapshot {
        let decoder = JSONDecoder()
        guard let scan = try decoder.decode(LaundryEnvelope<LaundryScan>.self,from:scanData).data,
              let info = try decoder.decode(LaundryEnvelope<LaundryInfo>.self,from:infoData).data else { throw LaundryError.response }
        guard try decoder.decode(LaundryEnvelope<LaundryScan>.self,from:scanData).code == 0,
              try decoder.decode(LaundryEnvelope<LaundryInfo>.self,from:infoData).code == 0 else { throw LaundryError.response }
        return try snapshot(scan:scan,info:info,expected:expectedDeviceId)
    }
}
