import Foundation

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
