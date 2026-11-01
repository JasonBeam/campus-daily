import Foundation

/// Reads used by onboarding (area tree + controllers). Implemented by `LxtClient` (direct,
/// signed locally).
public protocol ShowerDirectory: Sendable {
    /// Children of `parent` (the platform school id gives the campuses).
    func areas(parent: String) async throws -> [AreaNode]
    /// Rooms under a floor.
    func rooms(floor: String) async throws -> [AreaNode]
    func machines(room: String, schoolId: String) async throws -> [ShowerMachine]
}

/// The two money calls. Errors: `rejected`/`badRequest`/`sessionExpired` are definite refusals;
/// everything else is `uncertain` (the request may have taken effect).
public protocol ShowerGateway: Sendable {
    func authorize(_ binding: ShowerBinding, frame: Data) async throws -> ShowerAuthorization
    func settle(_ binding: ShowerBinding, frame: Data) async throws -> ShowerReceipt
}

public enum LxtEndpoints {
    public static let base = "https://isv.lxt6.cn"
    public static let userMsg = "AECC/GDBusinessSchool/getUserMsg"
    public static let areaInfo = "zk_areainfo_api/areaInfo/getAreaInfoForApplests"
    public static let roomInfo = "zk_areainfo_api/areaInfo/getAreaForRoomApplests"
    public static let machines = "ZK_BSRS/bathe/getMachineMacAddress"
    public static let authorize = "ZK_BSRS/GDBusinessSchool/bathingConsumptionAuthorization"
    public static let settle = "ZK_BSRS/GDBusinessSchool/analysisOfBathingConsumptionData"
    /// The platform's id for this school (first `getUserMsg` field and the area-tree root).
    public static let platformSchoolID = "20021"
    public static let maxListRows = 1000
    public static let maxMachines = 100
}

/// isv.lxt6.cn, signed with the local platform profile. Reads are GET with the signed query;
/// authorize/settle are POST form bodies with the same three fields.
public struct LxtClient: ShowerDirectory, ShowerGateway {
    let http: HTTPClient
    let profile: ShowerPlatformProfile
    /// `random(alphabet)` → 6 characters. Injected for golden tests.
    let random: @Sendable (String) -> String

    public init(http: HTTPClient, profile: ShowerPlatformProfile,
                random: @escaping @Sendable (String) -> String = { LxtSigning.random($0) }) {
        self.http = http; self.profile = profile; self.random = random
    }

    // MARK: Reads

    /// `getUserMsg` (`requestType=1`) with the school's `getSignData.appdata`.
    public func userInfo(_ h: ShowerHandoff) async throws -> ShowerUser {
        var fields = [("schoolid", LxtEndpoints.platformSchoolID)]
        for (k, v) in [("vsuppid", h.vsuppid), ("appid", h.appid), ("userId", h.userId), ("deptId", h.deptId),
                       ("username", h.username), ("phone", h.phone)] {
            // As the existing clients: every hand-off field is required.
            guard !v.isEmpty, v.utf8.count <= 2048 else { throw ServiceError.malformed(.ecykt, "appdata.\(k)") }
            fields.append((k, v))
        }
        fields.append(("random", random(LxtSigning.userMsgAlphabet)))
        let root = try await read(LxtEndpoints.userMsg, fields, requestType: true)
        guard let data = ResponseDecoding.data(root), data.object != nil else { throw ServiceError.malformed(.lxt6, "Data") }
        guard let student = data["studentid"]?.text, Self.isIdentifier(student) else { throw ServiceError.malformed(.lxt6, "Data.studentid") }
        guard let school = data["schoolid"]?.text, Self.isIdentifier(school) else { throw ServiceError.malformed(.lxt6, "Data.schoolid") }
        return ShowerUser(studentId: student, schoolId: school)
    }

    public func areas(parent: String) async throws -> [AreaNode] {
        try Self.nodes(try await read(LxtEndpoints.areaInfo, [("id", parent)]))
    }

    public func rooms(floor: String) async throws -> [AreaNode] {
        try Self.nodes(try await read(LxtEndpoints.roomInfo, [("id", floor)]))
    }

    public func machines(room: String, schoolId: String) async throws -> [ShowerMachine] {
        let root = try await read(LxtEndpoints.machines, [("typeId", profile.typeId), ("schoolId", schoolId), ("roomId", room)])
        guard let list = ResponseDecoding.data(root)?["objList"]?.array else { throw ServiceError.malformed(.lxt6, "data.objList") }
        guard list.count <= LxtEndpoints.maxMachines else { throw ServiceError.malformed(.lxt6, "data.objList") }
        return try list.enumerated().map { i, row in
            guard let id = row["machineId"]?.text, HexCoding.isHex(id, bytes: 4) else { throw ServiceError.malformed(.lxt6, "data.objList[\(i)].machineId") }
            guard let name = row["machineName"]?.text else { throw ServiceError.malformed(.lxt6, "data.objList[\(i)].machineName") }
            guard let mac = row["Mac"]?.text else { throw ServiceError.malformed(.lxt6, "data.objList[\(i)].Mac") }
            return ShowerMachine(machineId: id, name: name, mac: mac)
        }
    }

    // MARK: Money (state-changing)

    public func authorize(_ b: ShowerBinding, frame: Data) async throws -> ShowerAuthorization {
        let data = try await operation(LxtEndpoints.authorize, b, frame: frame, name: "authorize")
        return try Self.authorization(data)
    }

    public func settle(_ b: ShowerBinding, frame: Data) async throws -> ShowerReceipt {
        let data = try await operation(LxtEndpoints.settle, b, frame: frame, name: "settle")
        return ShowerReceipt.parse(pay: data["pay"])
    }

    /// Authorize reply decoder: `{machineid, studentId (4-byte hex authorization id), systemData (15-byte hex)}`.
    /// Anything unusable after a success code is `uncertain`: the authorization may exist.
    public static func authorization(_ data: JSONValue) throws -> ShowerAuthorization {
        guard data.object != nil,
              let machine = data["machineid"]?.text, !machine.isEmpty,
              let id = data["studentId"]?.text, HexCoding.isHex(id, bytes: 4),
              let hex = data["systemData"]?.text, let payload = HexCoding.data(hex),
              payload.count == ShowerFrames.authorizationLength else {
            throw ServiceError.uncertain(.lxt6)
        }
        return ShowerAuthorization(machineID: machine.uppercased(), payload: payload, authorizationID: id.uppercased())
    }

    // MARK: Plumbing

    static func isIdentifier(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9.-]{1,64}$", options: .regularExpression) != nil
    }

    static func nodes(_ root: JSONValue) throws -> [AreaNode] {
        guard let rows = ResponseDecoding.data(root)?.array else { throw ServiceError.malformed(.lxt6, "data") }
        guard rows.count <= LxtEndpoints.maxListRows else { throw ServiceError.malformed(.lxt6, "data") }
        let nodes = try rows.enumerated().map { i, row -> AreaNode in
            guard let id = row["id"]?.text, !id.isEmpty, id.count <= 1024 else { throw ServiceError.malformed(.lxt6, "data[\(i)].id") }
            guard let name = row["name"]?.text, !name.isEmpty, name.count <= 128 else { throw ServiceError.malformed(.lxt6, "data[\(i)].name") }
            return AreaNode(id: id, name: name)
        }
        guard Set(nodes.map(\.id)).count == nodes.count else { throw ServiceError.malformed(.lxt6, "data.id") }
        return nodes
    }

    private func read(_ path: String, _ fields: [(String, String)], requestType: Bool = false) async throws -> JSONValue {
        let query = LxtSigning.signedForm(fields, secret: profile.secret, sid: profile.sid, requestType: requestType)
        guard let url = URL(string: LxtEndpoints.base + "/" + path + "?" + query) else { throw ServiceError.badRequest(.lxt6) }
        let req = HTTPRequest(service: .lxt6, method: .get, url: url,
                              headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
                              bodyLimit: HTTPRequest.largeBodyLimit, logName: url.lastPathComponent)
        return try Self.decodeRead(try await http.send(req))
    }

    private func operation(_ path: String, _ b: ShowerBinding, frame: Data, name: String) async throws -> JSONValue {
        // Checked before anything leaves: a frame from another controller is never sent.
        guard ShowerFrames.identity(frame) == b.machineId.uppercased() else { throw ServiceError.badRequest(.lxt6) }
        let rand = random(LxtSigning.operationAlphabet)
        guard LxtSigning.isValidOperationRandom(rand) else { throw ServiceError.badRequest(.lxt6) }
        let fields = LxtSigning.operationFields(studentId: b.studentId, schoolId: b.schoolId, machineId: b.machineId, frame: frame,
                                                typeId: profile.typeId, version: profile.version, random: rand)
        let body = LxtSigning.signedForm(fields, secret: profile.secret, sid: profile.sid)
        guard let url = URL(string: LxtEndpoints.base + "/" + path) else { throw ServiceError.badRequest(.lxt6) }
        let req = HTTPRequest(service: .lxt6, method: .post, url: url,
                              headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
                              body: Data(body.utf8), isStateChanging: true, logName: name)
        return try Self.decodeOperation(try await http.send(req))
    }

    /// Unwraps an lxt6 body: JSON object, or a JSON **string** holding the object (AECC errors).
    static func root(_ body: Data) -> JSONValue? {
        guard var value = try? JSONValue.parse(body) else { return nil }
        if case .string(let s) = value, let inner = try? JSONValue.parse(s), inner.object != nil { value = inner }
        return value.object != nil ? value : nil
    }

    /// Envelope code mapping shared by reads and operations (both casings, `code`/`Code`).
    static func check(_ root: JSONValue, code: String) throws {
        switch code {
        case "0": return
        case "4002", "-301": throw ServiceError.badRequest(.lxt6)
        default: throw ServiceError.rejection(.lxt6, code: code, message: ResponseDecoding.message(root))
        }
    }

    /// Reads: non-2xx → `rejected("HTTP n")`; unreadable → `malformed`.
    static func decodeRead(_ response: HTTPResponse) throws -> JSONValue {
        guard (200..<300).contains(response.status) else {
            throw ServiceError.rejected(.lxt6, code: "HTTP \(response.status)", message: "")
        }
        guard let root = root(response.body) else { throw ServiceError.malformed(.lxt6, "$") }
        guard let code = ResponseDecoding.code(root), Int(code) != nil else { throw ServiceError.malformed(.lxt6, "code") }
        try check(root, code: code)
        return root
    }

    /// Authorize/settle: only HTTP 200 + readable JSON + an explicit integer code is an answer.
    /// Non-zero code → definite refusal; anything less certain → `uncertain`.
    static func decodeOperation(_ response: HTTPResponse) throws -> JSONValue {
        guard response.status == 200, let root = root(response.body),
              let code = ResponseDecoding.code(root), Int(code) != nil else { throw ServiceError.uncertain(.lxt6) }
        try check(root, code: code)
        guard let data = ResponseDecoding.data(root), data.object != nil else { throw ServiceError.uncertain(.lxt6) }
        return data
    }
}
