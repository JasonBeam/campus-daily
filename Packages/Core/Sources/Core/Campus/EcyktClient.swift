import Foundation

/// ecykt.gdbtu.edu.cn `/ykt-mini`. Every call is a JSON POST with `acc_token` in the header
/// **and** the body. No `timestamp` is sent (the server ignores it; the CSA login has none).
///
/// Only `loginBySysId`, `getSysBindCustInfo` and `getSignData` validate the token. Balance and
/// electricity do not signal expiry: use `boundCards` as the liveness check.
public struct EcyktClient: Sendable {
    let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    enum Referer {
        case recharge, power(areacode: String)
        var url: String {
            switch self {
            case .recharge: return "https://ecykt.gdbtu.edu.cn/ykt-view/recharge?isbind=1"
            case .power(let a): return "https://ecykt.gdbtu.edu.cn/ykt-view/powernew?interfaceName=powernew_\(FormEncoding.encode(a))&isbind=1"
            }
        }
    }

    // MARK: Login

    /// `POST /verify/csalogintoken/{areacode} {ticket}` → `{syscustid, isbind, status, token}`.
    /// Not yet captured live: shape from the official page's JS.
    public func exchange(ticket: String, areacode: String = EcyktSession.defaultAreacode,
                         userAgent: String = EcyktSession.defaultUserAgent) async throws -> EcyktLogin {
        guard let url = URL(string: SchoolEndpoints.ecyktBase.absoluteString + "/verify/csalogintoken/" + FormEncoding.encode(areacode)) else {
            throw ServiceError.badRequest(.ecykt)
        }
        let req = HTTPRequest.postJSON(service: .ecykt, url: url, headers: baseHeaders(userAgent: userAgent, referer: nil),
                                       json: ["ticket": .string(ticket)], logName: "csalogintoken")
        let data = try await decode(try await http.send(req), validating: true)
        return try login(from: data)
    }

    /// `getSysBindCustInfo` — the liveness check (validates the token).
    public func boundCards(_ s: EcyktSession) async throws -> [BoundCard] {
        let data = try await call("/api/customer/getSysBindCustInfo", s, validating: true, extra: [
            "areacode": .string(s.areacode), "version": .string(SchoolEndpoints.ecyktVersion), "appid": .string(SchoolEndpoints.ecyktAppID),
        ])
        guard let rows = data.array else { throw ServiceError.malformed(.ecykt, "data") }
        return try rows.enumerated().map { i, row in
            guard row.object != nil, let custid = row["custid"]?.text, !custid.isEmpty else {
                throw ServiceError.malformed(.ecykt, "data[\(i)].custid")
            }
            return BoundCard(custid: custid, unionID: row["custunionid"]?.text,
                             displayName: row["custname"]?.text ?? "", areaName: row["areaname"]?.text, raw: row)
        }
    }

    /// `loginBySysId` — mints a new token on every call (old ones are not revoked). Use only
    /// to build a recharge web session.
    public func freshLogin(_ s: EcyktSession) async throws -> EcyktLogin {
        let data = try await call("/api/customer/loginBySysId", s, validating: true, extra: [
            "areacode": .string(s.areacode), "version": .string(SchoolEndpoints.ecyktVersion),
            "appid": .string(SchoolEndpoints.ecyktAppID), "redirect": .string("/recharge?isbind=1"),
        ])
        return try login(from: data)
    }

    /// `getSignData` — the hand-off to the hot-water platform (validates the token).
    public func signData(_ s: EcyktSession, custid: String) async throws -> ShowerHandoff {
        // The captured official request sends `timestamp: ""` here.
        let data = try await call("/api/customer/getSignData", s, validating: true, extra: [
            "custid": .string(custid), "timestamp": .string(""),
        ])
        guard let app = data["appdata"], app.object != nil else { throw ServiceError.malformed(.ecykt, "data.appdata") }
        func f(_ k: String) throws -> String {
            guard let v = app[k]?.text, !v.isEmpty else { throw ServiceError.malformed(.ecykt, "data.appdata.\(k)") }
            return v
        }
        return ShowerHandoff(vsuppid: try f("vsuppid"), appid: try f("appid"), userId: try f("userId"),
                            deptId: try f("deptId"), username: try f("username"), phone: app["phone"]?.text ?? "",
                            sign: try f("sign"), nonce: try f("nonce"), timestamp: try f("timestamp"))
    }

    // MARK: Reads (do NOT validate the token)

    /// `scanpay/getUserBalance` → yuan number.
    public func balance(_ s: EcyktSession, custid: String) async throws -> Money {
        let data = try await call("/scanpay/getUserBalance", s, validating: false, extra: ["custid": .string(custid)])
        let money: Money?
        switch data {
        case .int(let i): money = Money(fen: Int(i) * 100)
        case .double(let d): money = Money(yuanNumber: d)
        case .string(let t): money = Money(yuanString: t)
        default: money = nil
        }
        guard let money else { throw ServiceError.malformed(.ecykt, "data") }
        return money
    }

    /// `card/getRecordList` (wallet history). Dates are `yyyyMMdd`.
    public func cardRecords(_ s: EcyktSession, custid: String, begin: String, end: String,
                            page: Int = 1, pageSize: Int = 20, timeout: TimeInterval? = nil) async throws -> CardRecordPage {
        let data = try await call("/card/getRecordList", s, validating: false, timeout: timeout, extra: [
            "custid": .string(custid), "begin": .string(begin), "end": .string(end), "datetype": .int(1),
            "pageNum": .int(Int64(page)), "pageSize": .int(Int64(pageSize)), "dcflag": .string(""), "address": .string(""),
        ])
        guard let rows = data["rows"]?.array else { throw ServiceError.malformed(.ecykt, "data.rows") }
        let records = try rows.enumerated().map { i, row -> CardRecord in
            guard let amountText = row["amount"]?.text, let amount = Money(yuanString: amountText) else {
                throw ServiceError.malformed(.ecykt, "data.rows[\(i)].amount")
            }
            return CardRecord(date: row["transdate"]?.text ?? row["accdate"]?.text ?? "",
                              time: row["transtime"]?.text ?? row["acctime"]?.text ?? "",
                              title: row["transname"]?.text ?? "",
                              amount: amount,
                              balanceAfter: row["balance"]?.text.flatMap(Money.init(yuanString:)),
                              direction: row["dcflag"]?.text,
                              voucher: Self.voucher(row["voucherno"]))
        }
        return CardRecordPage(total: data["total"]?.intValue, rows: records)
    }

    /// A record's voucher number as sent: a string or an exact integer. A number read as a
    /// double may have lost digits (two purchases could share it): no voucher then.
    static func voucher(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let s)?: return s
        case .int(let i)?: return String(i)
        default: return nil
        }
    }

    /// `electricnew/service server=/api/getBuildingInfo`. `parent == nil` → campuses.
    public func buildings(_ s: EcyktSession, parent: String?) async throws -> [PowerNode] {
        var extra: [String: JSONValue] = ["server": .string("/api/getBuildingInfo"), "areacode": .string(s.areacode)]
        if let parent { extra["buildingID"] = .string(parent) }
        let rows = try await electricRows(s, extra: extra, name: "getBuildingInfo")
        return try rows.enumerated().map { i, row in
            guard let id = row["buildingID"]?.text, !id.isEmpty else { throw ServiceError.malformed(.ecykt, "data[\(i)].buildingID") }
            guard let name = row["buildingName"]?.text else { throw ServiceError.malformed(.ecykt, "data[\(i)].buildingName") }
            return PowerNode(id: id, name: name)
        }
    }

    /// `electricnew/service server=/api/getMeterStatus` for one node (the app reads rooms: 1 row).
    /// `[]` is a successful "no meter here".
    public func meters(_ s: EcyktSession, nodeID: String) async throws -> [Meter] {
        let rows = try await electricRows(s, extra: [
            "server": .string("/api/getMeterStatus"), "areacode": .string(s.areacode), "buildingID": .string(nodeID),
        ], bodyLimit: HTTPRequest.defaultBodyLimit, name: "getMeterStatus")
        return try rows.enumerated().map { i, row in try Self.meter(row, index: i) }
    }

    static func meter(_ row: JSONValue, index i: Int) throws -> Meter {
        guard let address = row["comAddress"]?.text, !address.isEmpty else { throw ServiceError.malformed(.ecykt, "data[\(i)].comAddress") }
        guard let name = row["piplineName"]?.text else { throw ServiceError.malformed(.ecykt, "data[\(i)].piplineName") }
        let online: Bool?
        switch row["onlineStatus"]?.text {
        case "在线": online = true
        case "离线": online = false
        default: online = nil
        }
        return Meter(comAddress: address, name: name,
                     leftMoney: row["leftMoney"]?.text.flatMap(Money.init(yuanString:)),
                     remainingKWh: DecimalText.parse(row["remaining"]?.text),
                     dailyUseKWh: DecimalText.parse(row["preUseDay"]?.text),
                     price: DecimalText.parse(row["price"]?.text),
                     online: online,
                     switchState: row["meterStatus"]?.text,
                     updatedAt: row["updateDateTime"]?.text)
    }

    /// `GET /api/electricnew/getPowerUrl?custid&syscustid` → the 302 `Location` (not followed).
    public func powerPageURL(_ s: EcyktSession, custid: String) async throws -> URL {
        let req = HTTPRequest(service: .ecykt, method: .get, url: Self.powerEntryURL(s, custid: custid),
                              headers: baseHeaders(userAgent: s.userAgent, referer: .recharge, token: s.token), logName: "getPowerUrl")
        let response = try await http.send(req)
        if response.status == 401 || response.status == 403 { throw ServiceError.rejected(.ecykt, code: "HTTP \(response.status)", message: "") }
        guard (300..<400).contains(response.status) else {
            if response.status == 200, response.isBodyEmpty { throw ServiceError.badRequest(.ecykt) }
            throw ServiceError.malformed(.ecykt, "status")
        }
        guard let location = response.header("Location"),
              let url = URL(string: location, relativeTo: SchoolEndpoints.ecyktOrigin)?.absoluteURL,
              url.host?.lowercased() == SchoolEndpoints.ecyktHost else {
            throw ServiceError.malformed(.ecykt, "Location")
        }
        return url
    }

    public static func powerEntryURL(_ s: EcyktSession, custid: String) -> URL {
        URL(string: SchoolEndpoints.ecyktBase.absoluteString + "/api/electricnew/getPowerUrl?custid="
            + FormEncoding.encode(custid) + "&syscustid=" + FormEncoding.encode(s.syscustid))!
    }

    // MARK: Plumbing

    func baseHeaders(userAgent: String, referer: Referer?, token: String? = nil) -> [String: String] {
        var h = ["Accept": "application/json", "Origin": SchoolEndpoints.ecyktOrigin.absoluteString, "User-Agent": userAgent]
        if let referer { h["Referer"] = referer.url }
        if let token { h["acc_token"] = token }
        return h
    }

    private func electricRows(_ s: EcyktSession, extra: [String: JSONValue], bodyLimit: Int = HTTPRequest.defaultBodyLimit,
                              name: String) async throws -> [JSONValue] {
        let data = try await call("/api/electricnew/service", s, validating: false, extra: extra,
                                  referer: .power(areacode: s.areacode), bodyLimit: bodyLimit, name: name)
        // `data` is a JSON **string** holding an array; accept a plain array too.
        switch data {
        case .array(let rows): return rows
        case .string(let text):
            guard let parsed = try? JSONValue.parse(text), let rows = parsed.array else {
                throw ServiceError.malformed(.ecykt, "data<json>")
            }
            return rows
        default:
            throw ServiceError.malformed(.ecykt, "data")
        }
    }

    private func call(_ path: String, _ s: EcyktSession, validating: Bool, timeout: TimeInterval? = nil, extra: [String: JSONValue],
                      referer: Referer = .recharge, bodyLimit: Int = HTTPRequest.defaultBodyLimit,
                      name: String? = nil) async throws -> JSONValue {
        var body = extra
        body["syscustid"] = .string(s.syscustid)
        body["acc_token"] = .string(s.token)
        guard let url = URL(string: SchoolEndpoints.ecyktBase.absoluteString + path) else { throw ServiceError.badRequest(.ecykt) }
        var req = HTTPRequest.postJSON(service: .ecykt, url: url,
                                       headers: baseHeaders(userAgent: s.userAgent, referer: referer, token: s.token),
                                       json: body, bodyLimit: bodyLimit, logName: name ?? url.lastPathComponent)
        req.timeout = timeout
        return try await decode(try await http.send(req), validating: validating)
    }

    /// ecykt envelope `{code, msg, data}`:
    /// - empty body (HTTP 200) → `badRequest` (missing/undecryptable params), never expiry
    /// - `code -1` → `sessionExpired` only for validating endpoints, else `rejected`
    /// - `code 500 "缺少参数"` → `badRequest`
    /// - HTTP 401/403 → `rejected("HTTP 40x")`, not expiry: ecykt reports a dead token as HTTP
    ///   200 `code -1`; a bare 401/403 comes from a gateway or rate limit and says nothing
    ///   about the login
    func decode(_ response: HTTPResponse, validating: Bool) async throws -> JSONValue {
        if response.status == 401 || response.status == 403 {
            throw ServiceError.rejected(.ecykt, code: "HTTP \(response.status)", message: "")
        }
        guard let root = try ResponseDecoding.json(response, service: .ecykt) else { throw ServiceError.badRequest(.ecykt) }
        guard root.object != nil, let code = ResponseDecoding.code(root) else { throw ServiceError.malformed(.ecykt, "code") }
        let message = ResponseDecoding.message(root)
        switch code {
        case "0":
            guard let data = ResponseDecoding.data(root), !data.isNull else { throw ServiceError.malformed(.ecykt, "data") }
            return data
        case "-1" where validating:
            throw ServiceError.sessionExpired(.ecykt)
        case "500" where message.contains("缺少参数"):
            throw ServiceError.badRequest(.ecykt)
        default:
            throw ServiceError.rejection(.ecykt, code: code, message: message)
        }
    }

    private func login(from data: JSONValue) throws -> EcyktLogin {
        guard data.object != nil else { throw ServiceError.malformed(.ecykt, "data") }
        guard let sys = data["syscustid"]?.text, !sys.isEmpty else { throw ServiceError.malformed(.ecykt, "data.syscustid") }
        guard let token = data["token"]?.text, !token.isEmpty else { throw ServiceError.malformed(.ecykt, "data.token") }
        return EcyktLogin(syscustid: sys, token: token, isbind: data["isbind"]?.intValue ?? 0, status: data["status"]?.text)
    }
}
