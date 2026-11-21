//
//  ShowerBalance.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import Foundation

/// The campus card's balance as hot water sees it (hot water is charged to the card): the
/// amount and when it was read. Raw values only; Shower never reads Campus or Snapshot.
public struct ShowerBalance: Sendable, Equatable {
    public var amount: Money
    public var readAt: Date

    public init(amount: Money, readAt: Date) {
        self.amount = amount; self.readAt = readAt
    }
}
