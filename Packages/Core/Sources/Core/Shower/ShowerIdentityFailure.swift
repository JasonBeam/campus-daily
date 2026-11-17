import Foundation

/// Why setup could not read the hot-water account (`LxtClient.userInfo`), as it tells the user:
/// the hot-water platform turning it down over the balance, or anything else (the school's
/// hand-off included). Hot water is then bound later from 设置 › 热水.
public enum ShowerIdentityFailure: Equatable, Sendable {
    case lowBalance, other

    public init(_ error: Error) {
        if case .rejected(.lxt6, _, let message)? = error as? ServiceError,
           HTTPReplyNote.balanceWords.contains(where: { message.contains($0) }) {
            self = .lowBalance
        } else {
            self = .other
        }
    }

    /// The first-run guide's line (warm theme).
    public var warmText: String {
        switch self {
        case .lowBalance: return "热水平台说余额不足，这次没绑上热水。在热水小程序充值后，到设置的「热水」里再绑。电费和校园卡照常用。"
        case .other: return "这次没读到热水账号，先跳过。之后到设置的「热水」里再绑，电费和校园卡照常用。"
        }
    }

    /// 清爽's setup line.
    public var clearText: String {
        switch self {
        case .lowBalance: return "热水平台提示余额不足，暂未绑定热水；充值后可在设置 › 热水中重新绑定，电费与校园卡不受影响"
        case .other: return "热水账号读取失败，暂未绑定热水；可在设置 › 热水中重新绑定，电费与校园卡不受影响"
        }
    }
}
