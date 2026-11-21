//
//  ClearCNY.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/10.
//

import Foundation

import Core

/// 清爽's amounts on the laundry page, its sheets' neighbours and the 订单 tab: 「¥4.00」 whatever
/// the phone's region (`ClearBalanceText.currency`; never 「CN¥4.00」).
enum ClearCNY {
    static func text(_ value: Decimal) -> String { ClearBalanceText.currency(value) }
}
