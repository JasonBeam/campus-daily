import Foundation

public enum OnboardingError: String, Error, LocalizedError {
    case login = "尚未连接校园卡，请完成学校官方登录后等待自动同步"
    case response = "暂时无法读取学校信息，请稍后重试"
    case seed = "请先导入热水平台配置，再选择宿舍"
    case identity = "热水身份未确认，请重新登录学校"
    case platform = "当前安装包未包含热水平台配置，请更新完整版本"
    public var errorDescription: String? { rawValue }
}

public enum OfficialCampusSession {
    public static func parse(_ data: Data) throws -> CampusConfig {
        guard data.count <= 65536,
              let root = try JSONSerialization.jsonObject(with: data) as? [String:Any],
              let login = root["loginInfo"] as? [String:Any] else { throw OnboardingError.login }
        func text(_ value: Any?) -> String {
            if let value = value as? String { return value }
            if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.stringValue }
            return ""
        }
        let card = root["custInfo"] as? [String:Any] ?? [:]
        let payload: [String:String] = [
            "syscustid":text(login["syscustid"]), "acc_token":text(root["logintoken"]),
            "areacode":text(root["schoolid"] ?? login["areacode"]),
            "custid":text(card["custid"] ?? login["custid"] ?? root["custid"]),
            "timestamp":text(login["timestamp"]), "userAgent":text(root["userAgent"])
        ]
        guard ["syscustid","acc_token","areacode","custid"].allSatisfy({ !(payload[$0] ?? "").isEmpty }),
              payload.values.allSatisfy({ $0.rangeOfCharacter(from:.controlCharacters) == nil }) else { throw OnboardingError.login }
        let config = try JSONDecoder().decode(CampusConfig.self,from:JSONSerialization.data(withJSONObject:payload))
        try config.validate()
        return config
    }
}

public struct DormOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct DormMachine: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let mac: String
    public init(id: String, name: String, mac: String) { self.id = id; self.name = name; self.mac = mac }
}

/// Shared protocol settings only. Never contains a student, room, machine or user session.
public struct WaterPlatformProfile: Codable, Sendable {
    public let secret: String
    public let sid: String
    public let bleName: String
    public let typeID: Int
    public let version: Int
    public let access: WaterAccessSession?
    /// A platform-only handoff file must not silently copy another student's
    /// account, room or controller. The same file works on both mobile clients.
    public static func parseImport(_ bytes: Data) throws -> Self {
        guard bytes.count <= 8192,
              let fields = try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              Set(fields.keys) == Set(["secret","sid","bleName","typeID","version"]) else { throw WaterError.invalidConfig }
        let value = try JSONDecoder().decode(Self.self,from:bytes)
        try value.validate(); return value
    }
    public func validate() throws {
        if let access {try access.validate();guard bleName == access.bleName, typeID == access.typeID, version == access.version else {throw WaterError.invalidConfig};return}
        guard !secret.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, secret.utf8.count <= 256,
              !sid.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, sid.utf8.count <= 128,
              !bleName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, bleName.utf8.count <= 64,
              [secret,sid,bleName].allSatisfy({$0.rangeOfCharacter(from:.controlCharacters) == nil}),
              (0...Int(Int32.max)).contains(typeID), (1...Int(Int32.max)).contains(version) else { throw WaterError.invalidConfig }
    }
    public init(legacy: WaterConfig) {
        secret = legacy.secret; sid = legacy.sid; bleName = legacy.bleName
        typeID = legacy.typeID; version = legacy.version
        access = legacy.access
    }
    public init(access: WaterAccessSession) {
        secret = "";sid = "";bleName = access.bleName;typeID = access.typeID;version = access.version;self.access = access
    }
    public func configuration(student: String, school: String, machine: String) throws -> WaterConfig {
        try validate()
        let value = WaterConfig(secret:secret,sid:sid,studentID:student,schoolID:school,machineID:machine,
            bleName:bleName,typeID:typeID,version:version,access:access)
        try value.validate(); return value
    }
    /// Replace only a settled remote configuration verified against this school account.
    public func migrateToDirect(_ previous: WaterConfig, owner: String, student: String,
        school: String, unresolved: Bool) throws -> WaterConfig {
        guard !unresolved else { throw WaterError.unresolved }
        try validate();try previous.validate()
        guard access == nil, let prior = previous.access, prior.campusOwner == owner,
              previous.studentID == student, previous.schoolID == school else { throw WaterError.invalidConfig }
        return try configuration(student:student,school:school,machine:previous.machineID)
    }
}

/// Onboarding reads only. Contains no binding, valve, payment or settlement route.
@MainActor public final class DormOnboardingProvider {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 20; options.timeoutIntervalForResource = 25
        options.httpShouldSetCookies = false; options.urlCache = nil
        self.session = session ?? URLSession(configuration:options,delegate:NoRedirect(),delegateQueue:nil)
    }
    public func identity(campus: CampusConfig, seed: WaterPlatformProfile) async throws -> (student: String, school: String) {
        try campus.validate()
        if let access = seed.access {try access.validate();guard access.campusOwner == campus.waterAccessOwner else {throw WaterError.invalidConfig};return (access.studentID,access.schoolID)}
        var req = URLRequest(url:URL(string:CampusProvider.base + "/ykt-mini/api/customer/getSignData")!)
        req.httpMethod = "POST"
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.setValue(campus.accToken,forHTTPHeaderField:"acc_token")
        req.httpBody = try JSONSerialization.data(withJSONObject:["syscustid":campus.syscustid,"custid":campus.custid,"acc_token":campus.accToken,"timestamp":campus.timestamp])
        let (bytes,response) = try await session.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OnboardingError.response }
        guard let data = try CampusParser.unwrap(bytes) as? [String:Any] else { throw OnboardingError.identity }
        var app = data["appdata"]
        if let text = app as? String, let bytes = text.data(using:.utf8), bytes.count <= 32768 { app = try JSONSerialization.jsonObject(with:bytes) }
        guard let own = app as? [String:Any] else { throw OnboardingError.identity }
        var fields = [("schoolid","20021")]
        for key in ["vsuppid","appid","userId","deptId","username","phone"] {
            guard let value = own[key] as? String, !value.isEmpty, value.utf8.count <= 2048 else { throw OnboardingError.identity }
            fields.append((key,value))
        }
        fields.append(("random",String(UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(6))))
        let root = try await call("AECC/GDBusinessSchool/getUserMsg",fields:fields,seed:seed,requestType:true)
        guard let body = root["Data"] as? [String:Any], let student = body["studentid"] as? String else { throw OnboardingError.identity }
        let school = (body["schoolid"] as? String) ?? (body["schoolid"] as? NSNumber)?.stringValue ?? ""
        guard !student.isEmpty, !school.isEmpty else { throw OnboardingError.identity }
        return (student,school)
    }
    private func call(_ path: String, fields: [(String,String)], seed: WaterPlatformProfile, requestType: Bool = false) async throws -> [String:Any] {
        let allowed = ["AECC/GDBusinessSchool/getUserMsg","zk_areainfo_api/areaInfo/getAreaInfoForApplests","zk_areainfo_api/areaInfo/getAreaForRoomApplests","ZK_BSRS/bathe/getMachineMacAddress"]
        guard allowed.contains(path), !seed.secret.isEmpty, seed.secret.utf8.count <= 256,
              !seed.sid.isEmpty, seed.sid.utf8.count <= 128 else { throw OnboardingError.response }
        let code = fields.map { "\($0.0)=\($0.1)" }.joined(separator:"*_")
        var url = URLComponents(string:"https://isv.lxt6.cn/" + path)!
        var params = [("wxcode",code),("sign",WaterProtocol.signature(secret:seed.secret,wxcode:code)),("sid",seed.sid)]
        if requestType { params.append(("requestType","1")) }
        url.percentEncodedQuery = params.map { WaterProtocol.encodeForm($0.0) + "=" + WaterProtocol.encodeForm($0.1) }.joined(separator:"&")
        var req = URLRequest(url:url.url!); req.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        let (bytes,response) = try await session.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count <= 1_048_576 else { throw OnboardingError.response }
        var parsed = try JSONSerialization.jsonObject(with:bytes,options:.fragmentsAllowed)
        if let text = parsed as? String { parsed = try JSONSerialization.jsonObject(with:Data(text.utf8)) }
        guard let root = parsed as? [String:Any], let code = (root["code"] ?? root["Code"]) as? NSNumber,
              CFGetTypeID(code) != CFBooleanGetTypeID(), code.intValue == 0 else { throw OnboardingError.response }
        return root
    }
    public func options(parent: String, rooms: Bool = false, seed: WaterPlatformProfile) async throws -> [DormOption] {
        if let access = seed.access {
            let root = try await WaterAccessClient().call("options",access:access,fields:["parent":parent])
            guard let rows = root["options"] as? [[String:Any]], rows.count <= 1000 else {throw OnboardingError.response}
            return try rows.map {row in
                guard let id = row["id"] as? String, id.count <= 1024, let name = row["name"] as? String, name.count <= 128 else {throw OnboardingError.response}
                return DormOption(id:id,name:name)
            }
        }
        let path = rooms ? "zk_areainfo_api/areaInfo/getAreaForRoomApplests" : "zk_areainfo_api/areaInfo/getAreaInfoForApplests"
        let root = try await call(path,fields:[("id",parent)],seed:seed)
        guard let list = root["data"] as? [[String:Any]], list.count <= 1000 else { throw OnboardingError.response }
        let values = try list.map { item -> DormOption in
            let id = (item["id"] as? String) ?? (item["id"] as? NSNumber)?.stringValue ?? ""
            guard !id.isEmpty, let name = item["name"] as? String, !name.isEmpty, name.count <= 128 else { throw OnboardingError.response }
            return DormOption(id:id,name:name)
        }
        guard Set(values.map(\.id)).count == values.count else { throw OnboardingError.response }
        return values
    }
    public func machines(room: String, school: String, seed: WaterPlatformProfile) async throws -> [DormMachine] {
        if let access = seed.access {
            let root = try await WaterAccessClient().call("machines",access:access,fields:["room":room])
            guard let rows = root["machines"] as? [[String:Any]], rows.count <= 100 else {throw OnboardingError.response}
            return try rows.map {row in
                guard let id = row["id"] as? String, Data(strictHex:id)?.count == 4,
                      let name = row["name"] as? String, let mac = row["mac"] as? String else {throw OnboardingError.response}
                return DormMachine(id:id,name:name,mac:mac)
            }
        }
        let root = try await call("ZK_BSRS/bathe/getMachineMacAddress",fields:[("typeId",String(seed.typeID)),("schoolId",school),("roomId",room)],seed:seed)
        guard let body = root["data"] as? [String:Any], let list = body["objList"] as? [[String:Any]], list.count <= 100 else { throw OnboardingError.response }
        return try list.map { item in
            guard let id = item["machineId"] as? String, let bytes = Data(strictHex:id), bytes.count == 4,
                  let name = item["machineName"] as? String, let mac = item["Mac"] as? String else { throw OnboardingError.response }
            return DormMachine(id:id.uppercased(),name:name,mac:mac)
        }
    }
}

/// Keep the two local parts of a dorm setup consistent, including first use.
@MainActor public enum WaterDormSaveTransaction {
    public static func perform(saveWater: () throws -> Void, saveCampus: () throws -> Void, rollbackWater: () throws -> Void) throws {
        try saveWater()
        do {try saveCampus()}
        catch {
            let campusError = error
            try rollbackWater()
            throw campusError
        }
    }
}
