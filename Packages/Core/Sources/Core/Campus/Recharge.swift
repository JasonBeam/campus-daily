import Foundation

public enum RechargeKind: String, Sendable, Codable, Equatable {
    case card, electricity
}

/// Recharge flow (architecture §3.3). Payment happens inside the school's web page; the app
/// only prepares the session, opens external pay apps on a user tap, and confirms by
/// re-reading the value. It never claims success without a changed value.
public enum RechargeState: Sendable, Equatable {
    case idle
    case checkingSession(RechargeKind, baseline: Money?, reloginUsed: Bool)
    case needsLogin(RechargeKind, baseline: Money?)
    case inPage(RechargeKind, baseline: Money?)
    case confirming(RechargeKind, baseline: Money?, attempt: Int)
    /// `delta` is nil when the value did not change within the attempts ("以学校记录为准").
    case finished(RechargeKind, delta: Money?)
    case failed(RechargeKind, ServiceError)
}

public enum RechargeEvent: Sendable, Equatable {
    case tapRecharge(RechargeKind, baseline: Money?)
    case sessionReady
    case sessionFailed(ServiceError)
    case reloggedIn
    case payLinkTapped(URL)
    case returnedFromPage
    case valueRead(Money?)
    case dismiss
}

public enum RechargeEffect: Sendable, Equatable {
    /// Liveness check, then `loginBySysId`, then build the web session.
    case prepareSession(RechargeKind)
    case showLogin
    case openWebPage(RechargeKind)
    case openExternal(URL)
    /// Re-read balance (card) or the room meter (electricity) after `delaySeconds`.
    case readValue(RechargeKind, delaySeconds: Int)
}

public enum RechargeReducer {
    public static let maxConfirmAttempts = 3
    /// 3 reads over 30 s.
    public static let confirmDelays = [5, 10, 15]
    private static let payPrefixes = ["alipays", "alipay", "weixin"]

    public static func reduce(_ state: RechargeState, _ event: RechargeEvent) -> (RechargeState, [RechargeEffect]) {
        switch (state, event) {
        case (.idle, .tapRecharge(let kind, let baseline)),
             (.finished, .tapRecharge(let kind, let baseline)),
             (.failed, .tapRecharge(let kind, let baseline)):
            return (.checkingSession(kind, baseline: baseline, reloginUsed: false), [.prepareSession(kind)])

        case (.checkingSession(let kind, let baseline, _), .sessionReady):
            return (.inPage(kind, baseline: baseline), [.openWebPage(kind)])

        case (.checkingSession(let kind, let baseline, let used), .sessionFailed(let e)):
            if e.isSessionExpired && !used { return (.needsLogin(kind, baseline: baseline), [.showLogin]) }
            return (.failed(kind, e), [])

        case (.needsLogin(let kind, let baseline), .reloggedIn):
            // Retry once after the user signs in again.
            return (.checkingSession(kind, baseline: baseline, reloginUsed: true), [.prepareSession(kind)])

        case (.inPage, .payLinkTapped(let url)):
            guard let scheme = url.scheme?.lowercased(), payPrefixes.contains(scheme) else { return (state, []) }
            return (state, [.openExternal(url)])

        case (.inPage(let kind, let baseline), .returnedFromPage):
            return (.confirming(kind, baseline: baseline, attempt: 1), [.readValue(kind, delaySeconds: confirmDelays[0])])

        case (.confirming(let kind, let baseline, let attempt), .valueRead(let value)):
            if let value, let baseline, value != baseline {
                return (.finished(kind, delta: value - baseline), [])
            }
            if attempt >= maxConfirmAttempts { return (.finished(kind, delta: nil), []) }
            return (.confirming(kind, baseline: baseline, attempt: attempt + 1),
                    [.readValue(kind, delaySeconds: confirmDelays[attempt])])

        case (_, .dismiss):
            return (.idle, [])

        default:
            return (state, [])
        }
    }
}

/// What the recharge page shows when its session could not be prepared.
public struct RechargeOpenIssue: Sendable, Equatable {
    public let text: String
    /// 重新登录学校账号 is offered: the login may be what failed.
    public let offersSignIn: Bool

    public init(text: String, offersSignIn: Bool = true) {
        self.text = text; self.offersSignIn = offersSignIn
    }

    public init(_ error: Error) {
        // The other process is refreshing (it holds the lease): nothing is wrong with the
        // login, so no sign-in is offered.
        if case .busy? = error as? SchoolLoginFailure { self.init(text: "正在更新，等一下再试。", offersSignIn: false); return }
        if let e = error as? ServiceError { self.init(text: e.userMessage); return }
        self.init(text: "学校页面暂时打不开，再试一次。")
    }
}
