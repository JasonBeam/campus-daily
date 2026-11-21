//
//  ShowerIdentityFailure.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/17.
//

import Foundation

/// Why setup could not read the hot-water account, as it tells the user: the campus-card
/// system turning the hand-off (`getSignData`) down over the balance, or anything else (the
/// hot-water platform's own refusals included: one that still carries the identity is not a
/// failure). Hot water is then bound later from
/// 设置 › 热水 (暖橙) or 设置 › 校园登录与宿舍 › 宿舍热水 (清爽).
public enum ShowerIdentityFailure: Equatable, Sendable {
    case lowBalance, other

    public init(_ error: Error) {
        if case .rejected(.ecykt, _, let message)? = error as? ServiceError,
           HTTPReplyNote.balanceWords.contains(where: { message.contains($0) }) {
            self = .lowBalance
        } else {
            self = .other
        }
    }

    /// The first-run guide's line (warm theme).
    public var warmText: String {
        switch self {
        case .lowBalance: return "学校校园卡系统说余额不足，这次没绑上热水。给校园卡充值后，到设置的「热水」里再绑。电费和校园卡余额照常能看。"
        case .other: return "这次没读到热水账号，先跳过。之后到设置的「热水」里再绑，电费和校园卡照常用。"
        }
    }

    /// 清爽's setup line.
    public var clearText: String {
        switch self {
        case .lowBalance: return "校园卡系统提示余额不足，暂未绑定热水；校园卡充值后可在设置 › 校园登录与宿舍 › 宿舍热水中重新绑定，电费与校园卡余额查询不受影响"
        case .other: return "热水账号读取失败，暂未绑定热水；可在设置 › 校园登录与宿舍 › 宿舍热水中重新绑定，电费与校园卡不受影响"
        }
    }
}
