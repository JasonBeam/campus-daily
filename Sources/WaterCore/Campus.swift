import Foundation
import CryptoKit

public enum CampusError: String, Error, LocalizedError, Sendable {
    case configuration = "请完成学校账号与宿舍设置"
    case expired = "校园登录需更新，请重新登录学校账号"
    case network = "暂时无法连接学校"
    case offline = "校园查询未联网，请检查本 App 的无线数据权限"
    case timedOut = "学校连接超时，稍后下拉重试"
    case secureConnection = "学校安全连接未建立，请检查网络和系统时间"
    case response = "学校未返回有效数据"
    case ambiguous = "宿舍或校园卡绑定不唯一，请在官方页面核对"
    public var errorDescription: String? { rawValue }
}

public struct CampusConfig: Codable, Sendable {
    public var syscustid: String
    public var accToken: String
    public var areacode: String
    public var meterID: String
    public var buildingID: String
    public var custid: String
    public var userAgent: String
    public var timestamp: String
    public var dormRoom: String
    public var campusVersion: String
    public var portalDormAddress: String
    enum CodingKeys: String, CodingKey {
        case syscustid, accToken = "acc_token", areacode, meterID, buildingID, custid, userAgent, timestamp
        case dormRoom = "dorm_room", campusVersion = "campus_version", portalDormAddress = "portal_dorm_address"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys, fallback: String = "") throws -> String {
            try c.decodeIfPresent(String.self, forKey: key) ?? fallback
        }
        syscustid = try text(.syscustid); accToken = try text(.accToken)
        areacode = try text(.areacode, fallback: "450010")
        meterID = try text(.meterID)
        buildingID = try text(.buildingID); custid = try text(.custid)
        userAgent = try text(.userAgent); timestamp = try text(.timestamp)
        dormRoom = try text(.dormRoom); campusVersion = try text(.campusVersion, fallback: "v1.1.55")
        portalDormAddress = try text(.portalDormAddress)
    }
    public func validate() throws {
        let values = [syscustid,accToken,areacode,meterID,buildingID,custid,userAgent,timestamp,dormRoom,campusVersion,portalDormAddress]
        guard !syscustid.isEmpty, !accToken.isEmpty, !areacode.isEmpty,
              values.allSatisfy({ $0.utf8.count <= 2048 && !$0.contains("\n") && !$0.contains("\r") }),
              dormRoom.count <= 80 else { throw CampusError.configuration }
    }
    public var cacheIdentity: String {
        SHA256.hash(data: Data(([syscustid,areacode,custid,buildingID,dormRoom] + (meterID.isEmpty ? [] : [meterID])).joined(separator: "\0").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

public struct CampusSnapshot: Codable, Sendable {
    public var owner: String
    public var balance: Decimal?
    public var balanceFetchedAt: Date?
    public var room: String?
    public var roomFetchedAt: Date?
    public var cardError: CampusError?
    public var roomError: CampusError?
    public var electricity: CampusElectricity?
    public var powerFetchedAt: Date?
    public var powerError: CampusError?
    public init(owner: String) { self.owner = owner }
    public mutating func recordPower(_ result: Result<CampusElectricity,CampusError>, at date: Date = Date()) {
        switch result {
        case .success(let value): electricity = value; powerFetchedAt = date; powerError = nil
        case .failure(let error): powerError = error
        }
    }
    public func powerIsStale(at date: Date = Date()) -> Bool {
        guard let stamp = powerFetchedAt else { return true }
        return powerError != nil || date.timeIntervalSince(stamp) > 1200 || date < stamp
    }
    public func balanceIsStale(at date: Date = Date()) -> Bool {
        guard let stamp = balanceFetchedAt else { return true }
        return cardError != nil || date.timeIntervalSince(stamp) > 1200 || date < stamp
    }
    public mutating func recordBalance(_ result: Result<Decimal, CampusError>, at date: Date = Date()) {
        switch result {
        case .success(let value): balance = value; balanceFetchedAt = date; cardError = nil
        case .failure(let error): cardError = error
        }
    }
    public mutating func recordRoom(_ result: Result<String, CampusError>, at date: Date = Date()) {
        switch result {
        case .success(let value): room = value; roomFetchedAt = date; roomError = nil
        case .failure(let error): roomError = error
        }
    }
}

extension CampusError: Codable {}

public enum CampusParser {
    public static func unwrap(_ bytes: Data) throws -> Any {
        guard bytes.count <= 65536, let root = try? JSONSerialization.jsonObject(with: bytes) as? [String:Any],
              let code = root["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID() else { throw CampusError.response }
        guard code.doubleValue == 0 else { throw CampusError.expired }
        guard let data = root["data"], !(data is NSNull) else { throw CampusError.response }
        if let text = data as? String, let raw = text.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed) { return parsed }
        return data
    }
    public static func amount(_ input: Any) throws -> Decimal {
        let raw: String
        if let number = input as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { throw CampusError.response }
            raw = number.stringValue
        } else if let text = input as? String { raw = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        else { throw CampusError.response }
        guard raw.range(of: "^[+-]?[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, abs(value) <= Decimal(1_000_000_000) else { throw CampusError.response }
        return value
    }
    public static func balance(_ input: Any) throws -> Decimal {
        try amount((input as? [String:Any])?["balance"] ?? input)
    }
    public static func room(_ input: Any) throws -> String {
        var data = input
        if let meters = data as? [Any] {
            guard meters.count == 1 else { throw CampusError.ambiguous }
            data = meters[0]
        }
        guard let meter = data as? [String:Any] else { throw CampusError.response }
        for key in ["piplineName","roomName"] {
            if let value = meter[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               value.count <= 80 { return value }
        }
        throw CampusError.response
    }
}

@MainActor public final class CampusProvider {
    public nonisolated static let base = "https://ecykt.gdbtu.edu.cn"
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let options = URLSessionConfiguration.ephemeral
            options.timeoutIntervalForRequest = 12; options.timeoutIntervalForResource = 18
            options.httpShouldSetCookies = false; options.urlCache = nil
            self.session = URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
        }
    }
    private func call(_ path: String, payload: [String:Any], config: CampusConfig, power: Bool = false, webDiagnostic: Bool = false) async throws -> Any {
        try config.validate()
        let allowed = ["/ykt-mini/api/customer/loginBySysId", "/ykt-mini/api/customer/getSysBindCustInfo",
                       "/ykt-mini/scanpay/getUserBalance", "/ykt-mini/api/electricnew/service"]
        guard allowed.contains(path) else { throw CampusError.configuration }
        var body: [String:Any] = ["syscustid":config.syscustid, "acc_token":config.accToken]
        payload.forEach { body[$0.key] = $0.value }
        if !config.timestamp.isEmpty { body["timestamp"] = config.timestamp }
        var request = URLRequest(url: URL(string: Self.base + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.base, forHTTPHeaderField: "Origin")
        request.setValue(config.accToken, forHTTPHeaderField: "acc_token")
        request.setValue(config.userAgent.isEmpty ? "Mozilla/5.0" : config.userAgent, forHTTPHeaderField: "User-Agent")
        let referer = power ? "/ykt-view/powernew?interfaceName=powernew_\(WaterProtocol.encodeForm(config.areacode))&isbind=1" : "/ykt-view/recharge?isbind=1"
        request.setValue(Self.base + referer, forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let bytes: Data, response: URLResponse
        do {
            try Task.checkCancellation()
            (bytes,response) = try await session.data(for: request)
            try Task.checkCancellation()
        }
        catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            #if DEBUG
            print("CAMPUS_READ_NETWORK urlError=\((error as? URLError)?.errorCode ?? 0)")
            #endif
            if let code = (error as? URLError)?.code {
                switch code {
                case .notConnectedToInternet, .dataNotAllowed: throw CampusError.offline
                case .timedOut: throw CampusError.timedOut
                case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                     .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .appTransportSecurityRequiresSecureConnection:
                    throw CampusError.secureConnection
                default: break
                }
            }
            throw CampusError.network
        }
        guard let http = response as? HTTPURLResponse else { throw CampusError.response }
        if http.statusCode == 401 || http.statusCode == 403 { throw CampusError.expired }
        guard http.statusCode == 200 else {
            #if DEBUG
            print("CAMPUS_READ_HTTP status=\(http.statusCode)")
            #endif
            throw CampusError.network
        }
        if webDiagnostic {
            let root = (try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] ?? [:]
            var message = (root["message"] as? String) ?? (root["msg"] as? String) ?? ""
            for privateValue in [config.accToken,config.syscustid,config.custid,config.timestamp,config.areacode] where !privateValue.isEmpty { message = message.replacingOccurrences(of:privateValue,with:"[redacted]") }
            message = message.replacingOccurrences(of:"[0-9]{6,}",with:"[redacted]",options:.regularExpression)
            var record: [String:Any] = ["path":path,"httpStatus":http.statusCode,"observedAt":ISO8601DateFormatter().string(from:Date()),"requestKeys":body.keys.sorted(),"message":String(message.prefix(300))]
            record["code"] = root["code"]
            if let payload = root["data"] as? [String:Any] {
                record["dataKeys"] = payload.keys.sorted()
                record["ownerMatches"] = (payload["syscustid"] as? String) == config.syscustid
            }
            if let cards = root["data"] as? [[String:Any]] { record["cardCount"] = cards.count; record["configuredCardMatches"] = cards.filter { ($0["custid"] as? String) == config.custid }.count }
            let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CampusCache",isDirectory:true)
            try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let url = directory.appendingPathComponent("recharge-diagnostics.json")
            var history = (try? Data(contentsOf:url)).flatMap { try? JSONSerialization.jsonObject(with:$0) as? [[String:Any]] } ?? []
            history.append(record)
            if let data = try? JSONSerialization.data(withJSONObject:Array(history.suffix(8))) { try? data.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]) }
        }
        return try CampusParser.unwrap(bytes)
    }
    public func webSession(config: CampusConfig) async throws -> CampusWebSession {
        // Use the official bridge request's required platform parameters. No financial route is invoked.
        let rawLogin = try await call("/ykt-mini/api/customer/loginBySysId",
            payload:["areacode":config.areacode,"version":config.campusVersion,"appid":"wx7077a0b57d156efe","redirect":"/recharge?isbind=1"],config:config,webDiagnostic:true)
        guard let login = rawLogin as? [String:Any] else { throw CampusError.response }
        try Task.checkCancellation()
        let rawCards = try await call("/ykt-mini/api/customer/getSysBindCustInfo",
            payload:["areacode":config.areacode,"version":config.campusVersion,"appid":"wx7077a0b57d156efe"],config:config,webDiagnostic:true)
        guard let cards = rawCards as? [[String:Any]] else { throw CampusError.response }
        try Task.checkCancellation()
        return try CampusWebSession.create(config:config,login:login,cards:cards)
    }
    public func balance(config: CampusConfig) async throws -> Decimal {
        // Match the existing Scriptable flow; a captured card identity remains a fallback.
        var balanceID = config.syscustid
        var login: Any?
        do {
            login = try await call("/ykt-mini/api/customer/loginBySysId", payload: [
                "areacode":config.areacode,"version":config.campusVersion,"appid":"wx7077a0b57d156efe",
                "redirect":"/recharge?isbind=1"], config: config)
        } catch is CancellationError { throw CancellationError() }
          catch { /* Retain the existing captured-card fallback for other login-bridge errors. */ }
        if let data = login as? [String:Any], let id = data["syscustid"] as? String, !id.isEmpty { balanceID = id }
        try Task.checkCancellation()
        var custid = config.custid
        if custid.isEmpty {
            let data = try await call("/ykt-mini/api/customer/getSysBindCustInfo", payload: [
                "areacode":config.areacode,"version":config.campusVersion,"appid":"wx7077a0b57d156efe"], config: config)
            guard let list = data as? [[String:Any]], list.count == 1,
                  let id = list[0]["custid"] as? String, !id.isEmpty else { throw CampusError.ambiguous }
            custid = id
        }
        let data = try await call("/ykt-mini/scanpay/getUserBalance", payload: ["syscustid":balanceID,"custid":custid], config: config)
        return try CampusParser.balance(data)
    }
    public func powerBuildings(config: CampusConfig, parent: String? = nil) async throws -> [CampusPowerBuilding] {
        var payload: [String:Any] = ["server":"/api/getBuildingInfo","areacode":config.areacode]
        if let parent { payload["buildingID"] = parent }
        let data = try await call("/ykt-mini/api/electricnew/service",payload:payload,config:config,power:true)
        return try CampusElectricityParser.buildings(data)
    }
    public func powerMeters(config: CampusConfig, building: String) async throws -> [CampusElectricity] {
        guard !building.isEmpty else { throw CampusError.configuration }
        let data = try await call("/ykt-mini/api/electricnew/service",payload:["server":"/api/getMeterStatus","areacode":config.areacode,"buildingID":building],config:config,power:true)
        return try CampusElectricityParser.meters(data)
    }
    public func electricity(config: CampusConfig) async throws -> CampusElectricity {
        let meters = try await powerMeters(config:config,building:config.buildingID)
        return try CampusElectricityParser.select(meters,id:config.meterID)
    }
    public func room(config: CampusConfig) async throws -> String {
        if config.buildingID.isEmpty {
            guard !config.dormRoom.isEmpty else { throw CampusError.configuration }
            return config.dormRoom
        }
        let data = try await call("/ykt-mini/api/electricnew/service", payload: [
            "server":"/api/getMeterStatus", "areacode":config.areacode,"buildingID":config.buildingID], config: config, power: true)
        return try CampusParser.room(data)
    }
}
