import Foundation

/// The remote systems the app talks to.
public enum Service: String, Sendable, Codable, CaseIterable {
    case cas, portal, ecykt, lxt6, ujing, feedback

    /// A refusal without the server's own words, naming who refused.
    var refusal: String {
        switch self {
        case .cas, .portal, .ecykt: return "学校系统这次没通过，再试一次。"
        case .lxt6: return "热水平台这次没通过，再试一次。"
        case .ujing: return "U净 这次没通过，再试一次。"
        case .feedback: return "反馈没发出去，再试一次。"
        }
    }
}

/// One error vocabulary for every client. Values never carry tokens, ids or bodies:
/// `rejected` keeps the server's own sentence (≤ 80 chars), `malformed` a field path.
public enum ServiceError: Error, Equatable, Sendable, Codable {
    /// No usable network (not connected, connection lost before send, DNS/host unreachable).
    case offline
    /// The request timed out.
    case timedOut
    /// TLS / certificate failure.
    case tls
    /// The service says the credential is dead.
    case sessionExpired(Service)
    /// The service answered "no" in its own words.
    case rejected(Service, code: String, message: String)
    /// Our parameters are wrong or stale (ecykt HTTP 200 + empty body, ecykt 500 缺少参数, lxt6 4002).
    case badRequest(Service)
    /// Unparseable reply or missing fields. The string is a field path, never a value.
    case malformed(Service, String)
    /// A state-changing request whose outcome we cannot know. Never retried blindly.
    case uncertain(Service)

    public static let maxMessageLength = 80

    /// Builds `rejected`, trimming the server sentence to `maxMessageLength` characters.
    public static func rejection(_ service: Service, code: String, message: String) -> ServiceError {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return .rejected(service, code: code, message: String(trimmed.prefix(maxMessageLength)))
    }

    public var isSessionExpired: Bool {
        if case .sessionExpired = self { return true }
        return false
    }

    /// True for errors that say nothing about the server's answer (the request may not
    /// have reached it, or the answer was lost/unreadable).
    public var isIndefinite: Bool {
        switch self {
        case .offline, .timedOut, .tls, .malformed, .uncertain: return true
        case .sessionExpired, .rejected, .badRequest: return false
        }
    }

    /// The outcome of a **state-changing** request: anything that is not a definite answer
    /// from the service becomes `uncertain`, so no caller can offer a blind retry.
    public func forStateChangingRequest(_ service: Service) -> ServiceError {
        isIndefinite ? .uncertain(service) : self
    }

    /// Short, user-facing Chinese text. The UI may override per screen.
    public var userMessage: String {
        switch self {
        case .offline: return "网络连不上，检查一下网络再试。"
        case .timedOut: return "等了半天没回应，再试一次。"
        case .tls: return "连接不安全，换个网络再试。"
        case .sessionExpired: return "登录过期了，重新登录一下。"
        case .rejected(let service, _, let message): return message.isEmpty ? service.refusal : message
        case .badRequest: return "信息对不上了，重新登录或重新选一下再试。"
        case .malformed: return "返回的内容不对，过一会儿再试。"
        case .uncertain: return "结果未确认，请先查看官方记录，不要重复操作。"
        }
    }
}
