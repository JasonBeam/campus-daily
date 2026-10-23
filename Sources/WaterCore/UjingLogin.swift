import Foundation

public enum UjingLoginError: String, Error, LocalizedError {
    case mobile = "请输入正确的 11 位手机号"
    case captcha = "请输入收到的验证码"
    case rejected = "U净未接受这次请求，请核对信息后重试"
    case verification = "U净要求额外验证，请先在官方客户端完成验证"
    case uncertain = "请求结果未确认，请勿连续获取验证码，稍后再试"
    public var errorDescription: String? { rawValue }
}

public struct UjingAccount: Codable, Sendable {
    public let id: String
    public let businessUserID: String
    public let token: String
    public let clientID: String
    public let userAgent: String
    public init(id: String, businessUserID: String, token: String, clientID: String, userAgent: String) {
        self.id = id; self.businessUserID = businessUserID; self.token = token; self.clientID = clientID; self.userAgent = userAgent
    }
    public func validate() throws {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }), id.count <= 32,
              !businessUserID.isEmpty, businessUserID.utf8.allSatisfy({ (48...57).contains($0) }), businessUserID.count <= 32,
              token.count > 20, token.count <= 4096, !token.contains(" "),
              [token,clientID,userAgent].allSatisfy({ $0.rangeOfCharacter(from:.controlCharacters) == nil }),
              UUID(uuidString:clientID) != nil, userAgent.count <= 512 else { throw UjingLoginError.rejected }
    }
    public var headers: [String:String] {
        ["Authorization":"Bearer " + token,"x-app-code":"BI","x-app-version":"2.4.18",
         "x-mobile-id":clientID,"x-mobile-brand":"apple","User-Agent":userAgent]
    }
}

/// Normal SMS flow observed in the official client. No challenge-disabling parameters.
@MainActor public final class UjingLoginProvider {
    private let session: URLSession
    private let clientID: String
    private let userAgent: String
    public init(clientID: String, userAgent: String, session: URLSession? = nil) {
        self.clientID = clientID; self.userAgent = userAgent
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
            config.urlCache = nil
            self.session = URLSession(configuration:config,delegate:NoRedirect(),delegateQueue:nil)
        }
    }
    public static func validMobile(_ value: String) -> Bool {
        value.count == 11 && value.first == "1" && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    private func request(_ path: String, mobile: String, captcha: String? = nil) async throws -> [String:Any] {
        guard Self.validMobile(mobile) else { throw UjingLoginError.mobile }
        guard UUID(uuidString:clientID) != nil, userAgent.rangeOfCharacter(from:.controlCharacters) == nil,
              ["/api/v1/captcha","/api/v1/login"].contains(path) else { throw UjingLoginError.rejected }
        var parts = URLComponents(string:"https://phoenix.ujing.online" + path)!
        if path == "/api/v1/captcha" { parts.queryItems = [.init(name:"mobile",value:mobile),.init(name:"type",value:"1")] }
        var req = URLRequest(url:parts.url!)
        req.setValue("ZI",forHTTPHeaderField:"x-app-code")
        req.setValue("2.4.18",forHTTPHeaderField:"x-app-version")
        req.setValue(clientID,forHTTPHeaderField:"x-mobile-id")
        req.setValue("apple",forHTTPHeaderField:"x-mobile-brand")
        req.setValue(userAgent,forHTTPHeaderField:"User-Agent")
        if path == "/api/v1/login" {
            guard let captcha, (4...8).contains(captcha.count), captcha.utf8.allSatisfy({ (48...57).contains($0) }) else { throw UjingLoginError.captcha }
            req.httpMethod = "POST"; req.setValue("application/json",forHTTPHeaderField:"Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject:["mobile":mobile,"captcha":captcha])
        }
        let data: Data; let response: URLResponse
        do { (data,response) = try await session.data(for:req) }
        catch { throw UjingLoginError.uncertain }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 65536,
              let root = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let code = root["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID() else { throw UjingLoginError.rejected }
        guard code.intValue == 0 else {
            let message = (root["message"] as? String ?? "").lowercased()
            if ["滑块","人机","风控","challenge","captcha required"].contains(where:message.contains) { throw UjingLoginError.verification }
            throw UjingLoginError.rejected
        }
        return root
    }
    public func sendCode(mobile: String) async throws { _ = try await request("/api/v1/captcha",mobile:mobile) }
    public func login(mobile: String, captcha: String) async throws -> UjingAccount {
        let root = try await request("/api/v1/login",mobile:mobile,captcha:captcha)
        return try Self.account(root:root,clientID:clientID,userAgent:userAgent)
    }
    public static func account(root: [String:Any], clientID: String, userAgent: String) throws -> UjingAccount {
        guard let code = root["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code.intValue == 0,
              let data = root["data"] as? [String:Any], let temporary = data["isTempToken"] as? Bool, !temporary,
              let token = data["token"] as? String else { throw UjingLoginError.verification }
        func identifier(_ value: Any?) throws -> String {
            if let value = value as? String, !value.isEmpty { return value }
            if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.stringValue }
            throw UjingLoginError.rejected
        }
        let account = try UjingAccount(id:identifier(data["id"]),businessUserID:identifier(data["userId"]),token:token,clientID:clientID,userAgent:userAgent)
        try account.validate(); return account
    }
}
