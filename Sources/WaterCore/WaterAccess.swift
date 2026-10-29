import Foundation
import CryptoKit

/// Per-student access only. The platform signing key never reaches the app.
public struct WaterAccessSession: Codable, Equatable, Sendable {
    public let token: String
    public let campusOwner: String
    public let expiresAt: Int64
    public let studentID: String
    public let schoolID: String
    public let bleName: String
    public let typeID: Int
    public let version: Int
    public var isCurrent: Bool {expiresAt > Int64(Date().timeIntervalSince1970 * 1000) + 60_000}
    public func validate() throws {
        guard token.range(of:"^[A-Za-z0-9_-]{43}$",options:.regularExpression) != nil,
              campusOwner.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,
              expiresAt > 0, [studentID,schoolID].allSatisfy({$0.range(of:"^[A-Za-z0-9.-]{1,64}$",options:.regularExpression) != nil}),
              !bleName.isEmpty, bleName.utf8.count <= 64, bleName.rangeOfCharacter(from:.controlCharacters) == nil,
              (0...Int(Int32.max)).contains(typeID), (1...Int(Int32.max)).contains(version) else {throw WaterError.invalidConfig}
    }
}

public extension CampusConfig {
    var waterAccessOwner: String {SHA256.hash(data:Data((areacode+"\0"+syscustid).utf8)).map {String(format:"%02x",$0)}.joined()}
}

public struct WaterAccessError: Error, LocalizedError, Sendable {
    public let status: Int
    public let code: String
    public var errorDescription: String? {
        switch code {
        case "school_login_required", "school_login_expired", "access_expired", "login_required":
            return "学校登录需更新，请重新登录学校账号"
        case "transactions_not_enabled": return "热水接入正在验收，暂未开放开始用水"
        case "water_unresolved": return "仍有未确认的热水记录，请先核对记录"
        case "wrong_device", "bind_required", "invalid_location": return "宿舍或水控需要重新核对，请返回宿舍设置"
        case "rate_limited": return "查询较频繁，请稍后重试"
        case "access_network_unavailable": return "无法连接热水接入服务，请检查网络后重试"
        default: return "热水在线接入暂时不可用，请稍后重新读取宿舍"
        }
    }
    public init(status: Int, code: String) {
        self.status = status
        self.code = code.range(of:"^[a-z][a-z0-9_]{0,63}$",options:.regularExpression) != nil ? code : "invalid_response"
    }
}

@MainActor public final class WaterAccessClient {
    public static let base = "https://campus-api.070688.xyz"
    public static let backup = "https://campus-daily-access.jasonbeam-campus.workers.dev"
    private static var healthy: (origin:String,until:Date)?
    private let session: URLSession
    private let probeService: Bool
    private let useSharedHealth: Bool
    public init(session: URLSession? = nil, probeService: Bool? = nil) {
        self.probeService = probeService ?? (session == nil)
        useSharedHealth = session == nil
        if let session {self.session = session}
        else {
            let options = URLSessionConfiguration.ephemeral
            options.timeoutIntervalForRequest = 20;options.timeoutIntervalForResource = 25
            options.httpShouldSetCookies = false; options.urlCache = nil
            self.session = URLSession(configuration:options,delegate:NoRedirect(),delegateQueue:nil)
        }
    }
    private func origin() async throws -> String {
        guard probeService else {return Self.base}
        if useSharedHealth, let healthy = Self.healthy, healthy.until > Date() {return healthy.origin}
        // Probe without credentials. Choose a known service before any POST;
        // authorization/settlement requests are never retried on another host.
        for candidate in [Self.base,Self.backup] {
            try Task.checkCancellation()
            var request = URLRequest(url:URL(string:candidate+"/health")!)
            request.timeoutInterval = 4
            guard let (bytes,response) = try? await session.data(for:request), bytes.count <= 4096,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                  body["service"] as? String == "campus-daily-access", body["protocol"] as? Int == 1,
                  body["configured"] as? Bool == true else {continue}
            if useSharedHealth {Self.healthy = (candidate,Date().addingTimeInterval(candidate == Self.base ? 300 : 15))}
            return candidate
        }
        throw WaterAccessError(status:0,code:"access_network_unavailable")
    }
    public func call(_ route: String, access: WaterAccessSession? = nil, fields: [String:Any]) async throws -> [String:Any] {
        guard ["connect","bootstrap","options","machines","bind","authorize","settle","status"].contains(route) else {throw WaterError.invalidConfig}
        let origin = try await origin()
        var request = URLRequest(url:URL(string:origin+"/v1/"+route)!)
        request.httpMethod = "POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let access {try access.validate();request.setValue("Bearer "+access.token,forHTTPHeaderField:"Authorization")}
        request.httpBody = try JSONSerialization.data(withJSONObject:fields)
        let (bytes,response): (Data,URLResponse)
        do {(bytes,response) = try await session.data(for:request)}
        catch {
            if useSharedHealth {Self.healthy = nil}
            if ["authorize","settle"].contains(route) {throw WaterError.networkUncertain}
            throw WaterAccessError(status:0,code:"access_network_unavailable")
        }
        guard bytes.count <= 1_048_576, let http = response as? HTTPURLResponse else {throw WaterError.provider}
        guard let body = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else {
            throw WaterAccessError(status:http.statusCode,code:"invalid_response")
        }
        guard http.statusCode == 200 else {throw WaterAccessError(status:http.statusCode,code:body["error"] as? String ?? "invalid_response")}
        return body
    }
    public func connect(_ campus: CampusConfig) async throws -> WaterAccessSession {
        try campus.validate()
        var fields: [String:Any] = ["syscustid":campus.syscustid,"acc_token":campus.accToken,"areacode":campus.areacode,"custid":campus.custid]
        if !campus.timestamp.isEmpty {fields["timestamp"] = campus.timestamp}
        let root = try await call("connect",fields:fields)
        let value = try JSONDecoder().decode(WaterAccessSession.self,from:JSONSerialization.data(withJSONObject:root))
        try value.validate();guard value.campusOwner == campus.waterAccessOwner else {throw WaterError.invalidConfig};return value
    }
    public func bind(access: WaterAccessSession, room: String, machine: String) async throws {
        let root = try await call("bind",access:access,fields:["room":room,"machineID":machine])
        guard root["bound"] as? Bool == true, root["machineID"] as? String == machine else {throw WaterError.wrongDevice}
    }
    public func bootstrap(access: WaterAccessSession, residence: String) async throws -> WaterAccessBootstrap {
        let root = try await call("bootstrap",access:access,fields:["residence":residence])
        return try WaterAccessBootstrap.parse(root,residence:residence)
    }
}

public struct WaterAccessBootstrap: Sendable {
    public let levels: [[DormOption]]
    public let path: [DormOption]
    public let machines: [DormMachine]
    public let matched: Bool
    public let transactionsEnabled: Bool
    public static func parse(_ root: [String:Any], residence: String) throws -> Self {
        func options(_ rows: [[String:Any]]) throws -> [DormOption] {
            guard rows.count <= 1000 else {throw OnboardingError.response}
            let values = try rows.map {row -> DormOption in
                guard let id = row["id"] as? String, !id.isEmpty, id.count <= 1024,
                      let name = row["name"] as? String, !name.isEmpty, name.count <= 128 else {throw OnboardingError.response}
                return DormOption(id:id,name:name)
            }
            guard Set(values.map(\.id)).count == values.count else {throw OnboardingError.response}
            return values
        }
        guard let rawLevels = root["levels"] as? [[[String:Any]]], (1...4).contains(rawLevels.count),
              let rawPath = root["path"] as? [[String:Any]], rawPath.count <= rawLevels.count,
              let rows = root["machines"] as? [[String:Any]], rows.count <= 100,
              let matched = root["matched"] as? Bool, let enabled = root["transactionsEnabled"] as? Bool else {throw OnboardingError.response}
        let levels = try rawLevels.map(options), path = try options(rawPath)
        guard path.enumerated().allSatisfy({levels[$0.offset].contains($0.element)}), matched == (path.count == 4) else {throw OnboardingError.response}
        if matched {
            guard let address = PortalDormAddress.parse(residence), path.enumerated().allSatisfy({address.matches($0.element.name,level:$0.offset)}) else {throw OnboardingError.response}
        } else {guard rows.isEmpty else {throw OnboardingError.response}}
        let machines = try rows.map {row -> DormMachine in
            guard let id = row["id"] as? String, Data(strictHex:id)?.count == 4,
                  let name = row["name"] as? String, let mac = row["mac"] as? String else {throw OnboardingError.response}
            return DormMachine(id:id.uppercased(),name:name,mac:mac)
        }
        guard Set(machines.map(\.id)).count == machines.count else {throw OnboardingError.response}
        return Self(levels:levels,path:path,machines:machines,matched:matched,transactionsEnabled:enabled)
    }
}
