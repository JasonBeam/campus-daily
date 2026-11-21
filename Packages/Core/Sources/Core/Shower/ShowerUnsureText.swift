//
//  ShowerUnsureText.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import Foundation

/// The words for each `ShowerUnsureReason`, in each theme: first what happened, then where to
/// look (the campus card's records) and when (about an hour). 暖橙 speaks plainly; 清爽 is
/// written, its clauses split by semicolons, without a closing full stop.
public enum ShowerUnsureText {
    public static func warm(_ reason: ShowerUnsureReason) -> String {
        switch reason {
        case .unfinishedOrderAtStart:
            return "学校说还有一单热水没结束，这次没开水。去学校热水小程序看看那一单，扣费去校园卡记录里看，要 1 小时左右才出现。"
        case .settleNoAnswer:
            return "结算发出去了，学校没回音，不知道扣没扣。先别再结算，过 1 小时左右去校园卡记录里看看。"
        case .closeNoAnswer:
            return "结束发出去了，水控还没回话。先看水停没停，停了就算洗完；费用看校园卡记录，扣费要 1 小时左右才出现。"
        case .startUnconfirmed:
            return "开水的结果没收到。有热水就照常洗，洗完点结束；费用看校园卡记录，扣费要 1 小时左右才出现。"
        case .settleRefused:
            return "学校没接受这次结算。去校园卡记录里看看扣了没有，扣费要 1 小时左右才出现。"
        case .unfinishedOrderAtSettle:
            return "学校说还有一单热水没结束，这次没结算上。去学校热水小程序看看那一单，扣费去校园卡记录里看，要 1 小时左右才出现。"
        case .settleNotSent:
            return "结算没发出去。去校园卡记录里看看这次扣了没有，扣费要 1 小时左右才出现。"
        case .other:
            return "这次的结果没确认。先别重复操作，去校园卡记录里看看扣了没有，扣费要 1 小时左右才出现。"
        }
    }

    public static func clear(_ reason: ShowerUnsureReason) -> String {
        switch reason {
        case .unfinishedOrderAtStart:
            return "学校仍有未完成的热水订单，本次未开水；请在官方热水小程序中核对该订单，费用可在校园卡消费明细中核对，扣费约 1 小时后入账"
        case .settleNoAnswer:
            return "结算请求已发出，学校尚未确认结果；请勿重复结算，可在校园卡消费明细中核对，扣费约 1 小时后入账"
        case .closeNoAnswer:
            return "结束指令已发出，水控尚未返回结束数据；请确认是否已停水，费用可在校园卡消费明细中核对，扣费约 1 小时后入账"
        case .startUnconfirmed:
            return "开水结果未确认；如有出水可正常使用，结束后请点「结束并结算」，费用可在校园卡消费明细中核对，扣费约 1 小时后入账"
        case .settleRefused:
            return "学校未接受本次结算；可在校园卡消费明细中核对，扣费约 1 小时后入账"
        case .unfinishedOrderAtSettle:
            return "学校仍有未完成的热水订单，本次未能结算；请在官方热水小程序中核对该订单，费用可在校园卡消费明细中核对，扣费约 1 小时后入账"
        case .settleNotSent:
            return "结算请求未发出；可在校园卡消费明细中核对，扣费约 1 小时后入账"
        case .other:
            return "本次结果未确认；请勿重复操作，可在校园卡消费明细中核对，扣费约 1 小时后入账"
        }
    }
}
