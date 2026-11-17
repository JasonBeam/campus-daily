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
    /// No network, or a school server error (5xx), before the password was sent: nothing was tried.
    case offline
    /// The password was sent and no answer came back (timeout, lost connection, cancelled, a 5xx).
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
    /// The phone could not store the login's device id (the Keychain refused the write):
    /// nothing was sent.
    case cannotSave

    /// The password the user typed stays in the field: nothing said it was wrong (it was not
    /// sent, or no answer came back), so it can be tried again as it is.
    public var keepsTypedPassword: Bool {
        switch self {
        case .busy, .offline, .noAnswer, .cannotSave: return true
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
        case .wrongCredentials, .cannotLoginDirectly, .offline, .noAnswer, .busy, .cannotSave:
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
/// logged (the HTTP log records host, request name and status only).
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
        if (500...599).contains(page.status) { throw SchoolLoginFailure.offline }
        guard page.status == 200, let execution = CASPage.execution(in: page.body) else {
            throw SchoolLoginFailure.cannotLoginDirectly
        }

        let keyURL = URL(string: "https://" + SchoolEndpoints.casHost + "/cas/jwt/publicKey")!
        let key = try await send(HTTPRequest(service: .cas, method: .get, url: keyURL, logName: "casPublicKey"), jar: &jar)
        if (500...599).contains(key.status) { throw SchoolLoginFailure.offline }
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
        ], body: Data(body.utf8), bodyLimit: HTTPRequest.largeBodyLimit, logName: "casLoginSubmit", replyNote: CASPage.replyNote),
                                  jar: &jar, carriesPassword: true)

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
        case 200, 401:
            // Apereo CAS re-renders the login page with 401 after a refused password.
            throw CASPage.classify(errors: CASPage.errors(in: post.body))
        case 500...599:
            // The school may have counted the attempt before its server failed.
            throw SchoolLoginFailure.noAnswer
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

/// Reading the CAS HTML: the password form's `execution`, and the error the page shows after a
/// refused login (`var errors = [...]`, or the error element of the usual CAS markup).
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

    /// Every string inside `var errors = [...]`; without that list, the text of each error
    /// element (`errors(markupIn:)`). Nil when the page has neither.
    static func errors(in body: Data) -> [String]? {
        let html = String(decoding: body, as: UTF8.self)
        return scriptErrors(html) ?? markupErrors(html)
    }

    private static func scriptErrors(_ html: String) -> [String]? {
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

    /// Apereo CAS puts a refusal in `<div id="msg" class="errors">`, `<span id="password.errors">`,
    /// `<div class="alert alert-danger">` or `id="errormsg"`: an element whose class has the word
    /// `errors` or `alert-danger`, or whose id is `errormsg` or ends in `errors`. Each one's visible
    /// text (tags, scripts and styles dropped, spaces collapsed); empty ones are skipped.
    static func markupErrors(_ html: String) -> [String]? {
        let open = #"<([A-Za-z][A-Za-z0-9]*)\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: open) else { return nil }
        let ns = html as NSString
        var texts: [String] = []
        var searchFrom = 0
        while searchFrom < ns.length,
              let m = regex.firstMatch(in: html, range: NSRange(location: searchFrom, length: ns.length - searchFrom)) {
            searchFrom = m.range.location + m.range.length
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            let attributes = ns.substring(with: m.range(at: 2))
            guard !["script", "style", "input", "meta", "link"].contains(name), isErrorElement(attributes),
                  let close = closingTag(name, in: ns, from: searchFrom) else { continue }
            let inner = ns.substring(with: NSRange(location: searchFrom, length: close - searchFrom))
            let text = visibleText(inner)
            if !text.isEmpty { texts.append(text) }
            searchFrom = close
        }
        return texts.isEmpty ? nil : texts
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = "\\b" + name + #"\s*=\s*["']([^"']*)["']"#
        guard let r = attributes.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let match = String(attributes[r])
        guard let q = match.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        return String(match[match.index(after: q)..<match.index(before: match.endIndex)])
    }

    private static func isErrorElement(_ attributes: String) -> Bool {
        let classes = (attribute("class", in: attributes) ?? "").lowercased().split(separator: " ").map(String.init)
        if classes.contains("errors") || classes.contains("alert-danger") { return true }
        let id = (attribute("id", in: attributes) ?? "").lowercased()
        return id == "errormsg" || id.hasSuffix("errors")
    }

    /// Where the element opened before `start` ends, counting nested elements of the same name.
    private static func closingTag(_ name: String, in ns: NSString, from start: Int) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "<(/?)" + name + #"\b[^>]*>"#, options: .caseInsensitive) else { return nil }
        var depth = 1
        for m in regex.matches(in: ns as String, range: NSRange(location: start, length: ns.length - start)) {
            let closing = m.range(at: 1).length > 0
            let selfClosing = ns.substring(with: m.range).hasSuffix("/>")
            if closing { depth -= 1 } else if !selfClosing { depth += 1 }
            if depth == 0 { return m.range.location }
        }
        return nil
    }

    /// The text a person sees: no scripts, styles or tags, a few entities decoded, spaces collapsed.
    static func visibleText(_ html: String) -> String {
        var s = html
        for pattern in [#"(?is)<script\b.*?</script>"#, #"(?is)<style\b.*?</style>"#, #"(?s)<!--.*?-->"#] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        for (entity, text) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: entity, with: text)
        }
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// A lock, captcha or check already in force: retrying here would only count towards it.
    static let blockers = ["验证码", "captcha", "已锁定", "已被锁定", "已冻结", "已被冻结", "安全验证", "二次", "频繁", "次数过多",
                           "is locked", "has been locked", "account locked"]
    /// Wording that says the account or password is wrong; it wins over a lock still to come.
    static let wrongWords = ["账号或密码", "用户名或密码", "帐号或密码", "账号或者密码", "用户名或者密码", "帐号或者密码",
                             "密码错误", "密码不正确", "账号不存在", "用户不存在", "invalid credentials", "bad credentials"]
    /// Other things the page may mention (a lock to come, SMS or phone login, an odd account).
    static let softBlockers = ["锁定", "冻结", "异常", "短信", "手机", "邮箱", "lock"]
    /// Vaguer refusals: a wrong password only when nothing else is mentioned.
    static let vagueWrongWords = ["认证失败", "登录失败"]

    /// A lock, captcha or check in force wins; then wrong-password wording (even next to a lock
    /// still to come); anything else mentioned goes to the school's page; a bare 认证失败 or
    /// 登录失败 is a wrong password.
    static func classify(errors: [String]?) -> SchoolLoginFailure {
        switch reason(errors: errors) {
        case .casWrong, .casVagueWrong: return .wrongCredentials
        default: return .cannotLoginDirectly
        }
    }

    /// Which rule of `classify` the errors met, as the request log's word for it.
    static func reason(errors: [String]?) -> HTTPReplyNote {
        let text = (errors ?? []).joined(separator: " ")
        guard !text.isEmpty else { return .casNoError }
        func has(_ words: [String]) -> Bool { words.contains { text.localizedCaseInsensitiveContains($0) } }
        if has(blockers) { return .casBlocked }
        if has(wrongWords) { return .casWrong }
        if has(softBlockers) { return .casSoftBlocked }
        return has(vagueWrongWords) ? .casVagueWrong : .casUnrecognised
    }

    /// The password POST's note: the rule a refused page (200 or 401) met; nothing otherwise.
    @Sendable static func replyNote(status: Int, body: Data) -> HTTPReplyNote? {
        status == 200 || status == 401 ? reason(errors: errors(in: body)) : nil
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
