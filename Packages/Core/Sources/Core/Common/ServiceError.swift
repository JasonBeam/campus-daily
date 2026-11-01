import Foundation

/// The remote systems the app talks to.
public enum Service: String, Sendable, Codable, CaseIterable {
    case cas, portal, ecykt, lxt6, ujing
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
        case .offline: return "网络连不上，稍后再试。"
        case .timedOut: return "学校系统响应太慢，稍后再试。"
        case .tls: return "安全连接失败，检查网络后再试。"
        case .sessionExpired: return "登录已过期，请重新登录。"
        case .rejected(_, _, let message): return message.isEmpty ? "学校系统拒绝了请求。" : message
        case .badRequest: return "请求参数不对，重新登录或重新选择后再试。"
        case .malformed: return "返回的内容看不懂，稍后再试。"
        case .uncertain: return "结果未确认，请先查看官方记录，不要重复操作。"
        }
    }
}
