import Foundation

public enum SchoolEndpoints {
    public static let portalOrigin = URL(string: "https://portal.gdbtu.edu.cn")!
    public static let ecyktOrigin = URL(string: "https://ecykt.gdbtu.edu.cn")!
    public static let ecyktBase = URL(string: "https://ecykt.gdbtu.edu.cn/ykt-mini")!
    public static let casHost = "cas.gdbtu.edu.cn"
    public static let portalHost = "portal.gdbtu.edu.cn"
    public static let ecyktHost = "ecykt.gdbtu.edu.cn"
    /// Where CAS sends the browser after login: the portal's student page.
    public static let casService = "https://portal.gdbtu.edu.cn/?path=https%3A%2F%2Fportal.gdbtu.edu.cn%2Fmain.html%23%2FStudent"
    /// The CAS password form, for the portal.
    public static var casLoginURL: URL {
        var c = URLComponents(string: "https://cas.gdbtu.edu.cn/cas/login")!
        c.queryItems = [URLQueryItem(name: "service", value: casService)]
        return c.url!
    }
    public static let rechargePage = URL(string: "https://ecykt.gdbtu.edu.cn/ykt-view/recharge?isbind=1")!
    /// Values the official ecykt web app sends.
    public static let ecyktVersion = "v1.1.55"
    public static let ecyktAppID = "wx7077a0b57d156efe"
}

/// Strict form encoding (RFC 3986 unreserved kept) for query values such as the
/// `custid`/`syscustid` ciphertexts, which contain `%`.
enum FormEncoding {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}

/// portal.gdbtu.edu.cn (`X-Id-Token`, `X-Device-Info: PC`, `X-Terminal-Info: PC`).
public struct PortalClient: Sendable {
    let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    /// `getMyInfo.gydz` → registered dorm address.
    public func myInfo(_ token: PortalToken) async throws -> PortalResidence {
        let data = try await get("/portalData/v2/personalData/getMyInfo", token: token, name: "getMyInfo")
        guard let gydz = data["gydz"]?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !gydz.isEmpty else {
            throw ServiceError.malformed(.portal, "data.gydz")
        }
        return PortalResidence(raw: gydz)
    }

    /// `getMyECard.pcUrl`: the ecykt entry URL carrying a fresh one-time CAS ticket.
    public func eCardTicketURL(_ token: PortalToken) async throws -> URL {
        let data = try await get("/portal-api/v2/personalData/getMyECard", token: token, name: "getMyECard")
        guard let text = data["pcUrl"]?.text, let url = URL(string: text),
              url.scheme == "https", url.host?.lowercased() == SchoolEndpoints.ecyktHost,
              CASTicket.extract(from: url) != nil else {
            throw ServiceError.malformed(.portal, "data.pcUrl")
        }
        return url
    }

    private func get(_ path: String, token: PortalToken, name: String) async throws -> JSONValue {
        guard let url = URL(string: "https://" + SchoolEndpoints.portalHost + path) else { throw ServiceError.badRequest(.portal) }
        let req = HTTPRequest(service: .portal, method: .get, url: url, headers: [
            "X-Id-Token": token.value, "X-Device-Info": "PC", "X-Terminal-Info": "PC", "Accept": "application/json",
        ], logName: name)
        let response = try await http.send(req)
        guard let root = try ResponseDecoding.json(response, service: .portal) else {
            throw ServiceError.malformed(.portal, "$")
        }
        guard let code = ResponseDecoding.code(root) else { throw ServiceError.malformed(.portal, "code") }
        switch code {
        case "0": break
        case "-1001", "-1": throw ServiceError.sessionExpired(.portal)
        default: throw ServiceError.rejection(.portal, code: code, message: ResponseDecoding.message(root))
        }
        guard let data = ResponseDecoding.data(root), data.object != nil else {
            throw ServiceError.malformed(.portal, "data")
        }
        return data
    }
}

/// The single-use CAS ticket inside `pcUrl`. Never logged.
public enum CASTicket {
    public static func extract(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "ticket" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
}
