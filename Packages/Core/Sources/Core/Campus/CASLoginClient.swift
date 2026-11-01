import Foundation
import Security

/// Why an account/password login did not produce a portal token. The UI maps each case to one
/// sentence; nothing here carries the server's text or any credential.
public enum SchoolLoginFailure: Error, Sendable, Equatable {
    /// The school said the account or password is wrong.
    case wrongCredentials
    /// Anything else the school put in the way (captcha, lock, extra verification, a page we
    /// don't recognise). The user signs in on the school's own web page instead.
    case cannotLoginDirectly
    /// No network before the password was sent: the school saw nothing.
    case offline
    /// The password was sent and no answer came back (timeout, lost connection, cancelled).
    /// The school may have counted it as an attempt, so automatic logins hold off for a while.
    case noAnswer
    /// Saving a password for an account other than the signed-in one: nothing was saved and
    /// nobody was switched (signing out comes first).
    case differentAccount
    /// The other process (the widget) is in the middle of a school refresh, which may log in
    /// itself: nothing was sent. Or it took the lease over while this login was out (the app was
    /// suspended past it) and may have stored newer credentials: what came back was not written.
    /// Try again in a moment.
    case busy
    /// Saving a password while the stored login can't be read (damaged, or an older shape): it
    /// can't be told who is signed in, so nothing was sent or saved. Signing out and in again
    /// fixes it.
    case unreadableAccount

    /// The password the user typed stays in the field: nothing said it was wrong (it was not
    /// sent, or no answer came back), so it can be tried again as it is.
    public var keepsTypedPassword: Bool {
        switch self {
        case .busy, .offline, .noAnswer: return true
        case .wrongCredentials, .cannotLoginDirectly, .differentAccount, .unreadableAccount: return false
        }
    }

    /// Why a password was not saved, as Settings says it (alert title and message).
    public struct SavePasswordRefusal: Sendable, Equatable {
        public var title: String
        public var message: String
        /// Both in one line, for places without an alert.
        public var text: String { title + message }
    }

    /// The two refusals that are not about the password itself; nil for every other failure.
    public var savePasswordRefusal: SavePasswordRefusal? {
        switch self {
        case .differentAccount:
            return SavePasswordRefusal(title: "这不是现在登录的账号，没保存。", message: "要换账号，先退出登录。")
        case .unreadableAccount:
            return SavePasswordRefusal(title: "认不出现在登录的是哪个账号，没保存。", message: "先退出登录，再重新登录一次。")
        case .wrongCredentials, .cannotLoginDirectly, .offline, .noAnswer, .busy:
            return nil
        }
    }
}

/// Account/password sign-in, for tests and the session (the real one is `CASLoginClient`).
public protocol SchoolPasswordLogin: Sendable {
    /// One login attempt, never retried. Throws `SchoolLoginFailure` (or `CancellationError`).
    func login(account: String, password: String, visitorID: String) async throws -> PortalToken
}

/// The school's CAS password form without a web view:
/// 1. `GET /cas/login?service=…` → keep the session cookie, read `execution`;
/// 2. `GET /cas/jwt/publicKey` → RSA public key (PEM);
/// 3. `POST /cas/login?service=…` with `"__RSA__" + base64(PKCS#1 v1.5(password))`, redirects
///    not followed → `Location` carries `ticket`, a JWT whose payload holds the portal `idToken`.
/// Cookies live only for one login. The password, ticket, idToken and `execution` are never
/// logged (the HTTP log records host, path and status only).
public struct CASLoginClient: SchoolPasswordLogin {
    let http: HTTPClient
    let now: @Sendable () -> Date

    public init(http: HTTPClient, now: @escaping @Sendable () -> Date = Date.init) {
        self.http = http; self.now = now
    }

    public func login(account: String, password: String, visitorID: String) async throws -> PortalToken {
        var jar = CASCookieJar()
        let loginURL = SchoolEndpoints.casLoginURL

        let page = try await send(HTTPRequest(service: .cas, method: .get, url: loginURL,
                                              headers: ["Accept": "text/html"],
                                              bodyLimit: HTTPRequest.largeBodyLimit, logName: "casLoginPage"), jar: &jar)
        guard page.status == 200, let execution = CASPage.execution(in: page.body) else {
            throw SchoolLoginFailure.cannotLoginDirectly
        }

        let keyURL = URL(string: "https://" + SchoolEndpoints.casHost + "/cas/jwt/publicKey")!
        let key = try await send(HTTPRequest(service: .cas, method: .get, url: keyURL, logName: "casPublicKey"), jar: &jar)
        guard key.status == 200, let encrypted = CASPassword.encrypt(password, publicKeyPEM: key.body) else {
            throw SchoolLoginFailure.cannotLoginDirectly
        }

        let fields: [(String, String)] = [
            ("username", account), ("password", encrypted), ("captcha", ""), ("currentMenu", "1"), ("failN", "0"),
            ("mfaState", ""), ("execution", execution), ("_eventId", "submit"), ("geolocation", ""),
            ("fpVisitorId", visitorID), ("trustAgent", ""), ("submit1", "Login1"),
        ]
        let body = fields.map { FormEncoding.encode($0.0) + "=" + FormEncoding.encode($0.1) }.joined(separator: "&")
        let post = try await send(HTTPRequest(service: .cas, method: .post, url: loginURL, headers: [
            "Content-Type": "application/x-www-form-urlencoded", "Accept": "text/html",
            "Origin": "https://" + SchoolEndpoints.casHost,
        ], body: Data(body.utf8), bodyLimit: HTTPRequest.largeBodyLimit, logName: "casLoginSubmit"), jar: &jar, carriesPassword: true)

        switch post.status {
        case 302, 303:
            guard let location = post.header("Location").flatMap(URL.init(string:)),
                  location.scheme == "https", location.host?.lowercased() == SchoolEndpoints.portalHost,
                  let ticket = CASTicket.extract(from: location),
                  let token = CASTicketClaims.portalToken(fromTicket: ticket) else {
                throw SchoolLoginFailure.cannotLoginDirectly
            }
            if let expiresAt = token.expiresAt, expiresAt <= now() { throw SchoolLoginFailure.cannotLoginDirectly }
            return token
        case 200:
            throw CASPage.classify(errors: CASPage.errors(in: post.body))
        default:
            throw SchoolLoginFailure.cannotLoginDirectly
        }
    }

    /// One request with this login's cookies; transport failures become `offline` or
    /// `cannotLoginDirectly`, never a retry. Once the password may have left the phone
    /// (`carriesPassword`), any failure to hear back, cancellation included, is `noAnswer`.
    private func send(_ request: HTTPRequest, jar: inout CASCookieJar, carriesPassword: Bool = false) async throws -> HTTPResponse {
        var r = request
        if let cookie = jar.header { r.headers["Cookie"] = cookie }
        let response: HTTPResponse
        do { response = try await http.send(r) }
        catch where carriesPassword { throw SchoolLoginFailure.noAnswer }
        catch is CancellationError { throw CancellationError() }
        catch let e as ServiceError {
            switch e {
            case .offline, .timedOut, .tls: throw SchoolLoginFailure.offline
            default: throw SchoolLoginFailure.cannotLoginDirectly
            }
        } catch { throw SchoolLoginFailure.offline }
        jar.take(response, from: request.url)
        return response
    }
}

/// Cookies for one login, CAS host only, kept in memory.
struct CASCookieJar {
    private(set) var values: [(String, String)] = []

    var header: String? { values.isEmpty ? nil : values.map { $0.0 + "=" + $0.1 }.joined(separator: "; ") }

    mutating func take(_ response: HTTPResponse, from url: URL) {
        guard url.host?.lowercased() == SchoolEndpoints.casHost else { return }
        let fields = response.headers.filter { $0.key.caseInsensitiveCompare("Set-Cookie") == .orderedSame }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            values.removeAll { $0.0 == cookie.name }
            values.append((cookie.name, cookie.value))
        }
    }
}

/// Reading the CAS HTML: the password form's `execution`, and the `var errors = [...]` the page
/// shows after a refused login.
enum CASPage {
    static func execution(in body: Data) -> String? {
        let html = String(decoding: body, as: UTF8.self)
        guard let form = html.range(of: "id=\"fm1\"") else { return nil }
        let rest = html[form.upperBound...]
        guard let name = rest.range(of: "name=\"execution\"") else { return nil }
        let tag = rest[name.upperBound...].prefix(16 * 1024)
        guard let open = tag.range(of: "value=\"") else { return nil }
        let value = tag[open.upperBound...].prefix { $0 != "\"" }
        guard !value.isEmpty, value.count < 16 * 1024, tag[open.upperBound...].count > value.count else { return nil }
        return String(value)
    }

    /// Every string inside `var errors = [...]`, or nil when the page has no such list.
    static func errors(in body: Data) -> [String]? {
        let html = String(decoding: body, as: UTF8.self)
        guard let start = html.range(of: #"var\s+errors\s*=\s*\["#, options: .regularExpression) else { return nil }
        var depth = 0, inString = false, escaped = false
        var end = html.index(before: start.upperBound)
        for i in html[end...].indices {
            let c = html[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true } else if c == "[" || c == "{" { depth += 1 }
            else if c == "]" || c == "}" { depth -= 1; if depth == 0 { end = i; break } }
        }
        guard depth == 0, html[end] == "]" else { return nil }
        let literal = html[html.index(before: start.upperBound)...end]
        guard let json = try? JSONValue.parse(Data(literal.utf8)) else { return nil }
        var texts: [String] = []
        func collect(_ v: JSONValue) {
            switch v {
            case .string(let s): texts.append(s)
            case .array(let a): a.forEach(collect)
            case .object(let o): o.keys.sorted().forEach { collect(o[$0]!) }
            default: break
            }
        }
        collect(json)
        return texts
    }

    /// Captcha, lock or extra verification wins over a wrong password: the user must go to the
    /// school's page either way, and retrying here would only count towards the lock.
    static func classify(errors: [String]?) -> SchoolLoginFailure {
        let text = (errors ?? []).joined(separator: " ")
        guard !text.isEmpty else { return .cannotLoginDirectly }
        let blockers = ["验证码", "锁定", "冻结", "安全验证", "异常", "短信", "手机", "邮箱", "二次", "频繁", "captcha", "lock"]
        if blockers.contains(where: { text.localizedCaseInsensitiveContains($0) }) { return .cannotLoginDirectly }
        let wrong = ["账号或密码", "用户名或密码", "帐号或密码", "密码错误", "密码不正确", "账号不存在", "用户不存在"]
        return wrong.contains(where: { text.contains($0) }) ? .wrongCredentials : .cannotLoginDirectly
    }
}

/// `"__RSA__" + base64(RSA PKCS#1 v1.5(password))` with the page's public key.
enum CASPassword {
    static func encrypt(_ password: String, publicKeyPEM: Data) -> String? {
        guard let der = PEM.der(String(decoding: publicKeyPEM, as: UTF8.self)),
              let pkcs1 = DER.rsaPublicKey(fromSPKI: der) ?? (DER.isSequence(der) ? der : nil) else { return nil }
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil),
              SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1),
              let sealed = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, Data(password.utf8) as CFData, nil) else {
            return nil
        }
        return "__RSA__" + (sealed as Data).base64EncodedString()
    }
}

enum PEM {
    static func der(_ text: String) -> Data? {
        let body = text.split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .filter { !$0.isWhitespace }
        guard !body.isEmpty else { return nil }
        return Data(base64Encoded: body)
    }
}

/// Just enough DER to take the RSA key out of a SubjectPublicKeyInfo.
enum DER {
    static func isSequence(_ d: Data) -> Bool { d.first == 0x30 }

    /// SEQUENCE { SEQUENCE { OID rsaEncryption, NULL }, BIT STRING { 0x00, RSAPublicKey } }
    static func rsaPublicKey(fromSPKI d: Data) -> Data? {
        let bytes = [UInt8](d)
        guard let outer = element(bytes, at: 0), outer.tag == 0x30 else { return nil }
        guard let algorithm = element(bytes, at: outer.contentStart), algorithm.tag == 0x30 else { return nil }
        let rsaOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        guard Array(bytes[algorithm.contentStart..<min(algorithm.end, algorithm.contentStart + rsaOID.count)]) == rsaOID,
              let bits = element(bytes, at: algorithm.end), bits.tag == 0x03,
              bits.contentStart < bits.end, bytes[bits.contentStart] == 0x00 else { return nil }
        return Data(bytes[(bits.contentStart + 1)..<bits.end])
    }

    private struct Element { var tag: UInt8; var contentStart: Int; var end: Int }

    private static func element(_ b: [UInt8], at i: Int) -> Element? {
        guard i + 1 < b.count else { return nil }
        var length = Int(b[i + 1]), start = i + 2
        if length & 0x80 != 0 {
            let n = length & 0x7F
            guard (1...3).contains(n), start + n <= b.count else { return nil }
            length = b[start..<(start + n)].reduce(0) { $0 << 8 | Int($1) }
            start += n
        }
        guard start + length <= b.count else { return nil }
        return Element(tag: b[i], contentStart: start, end: start + length)
    }
}

/// The CAS ticket is a JWT; its payload's `idToken` (itself a JWT, about 8 h) is the portal token.
/// Decoded locally, never verified or logged.
public enum CASTicketClaims {
    public static func portalToken(fromTicket ticket: String) -> PortalToken? {
        guard let claims = payload(ticket), let idToken = claims["idToken"]?.text, !idToken.isEmpty else { return nil }
        let exp = payload(idToken)?["exp"]?.intValue ?? claims["exp"]?.intValue
        return PortalToken(idToken, expiresAt: exp.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    static func payload(_ jwt: String) -> JSONValue? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let json = try? JSONValue.parse(data), json.object != nil else { return nil }
        return json
    }
}
