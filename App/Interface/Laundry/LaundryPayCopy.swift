//
//  LaundryPayCopy.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import Foundation
import Core

/// The pay sheet's words in each theme: 清爽's review and payment wording, 暖橙's own. The one
/// place they are written.
enum LaundryPayCopy {
    /// 清爽: a new order is reviewed (「核对订单」); an order already placed is paid with
    /// 「确认支付宝付款」. The same sheet draws both.
    enum Clear {
        struct Sheet: Equatable {
            let title: String
            let cancel: String
            let submit: String
            let machine: String
            let program: String?
            /// The sentence above the button (under either 洗衣方式 choice for a new order).
            let note: String
            /// A new order asks 洗衣方式; paying an existing one keeps its choice.
            let asksMode: Bool
        }

        static let reviewTitle = "核对订单"
        static let reviewCancel = "取消"
        static let reviewSubmit = "下单并前往支付宝"
        static let reviewNote = "确认后将预约这台机器并前往支付宝。付款可能扣款并启动设备，请提前放好衣物，实际金额以收银台为准。"
        static let payTitle = "确认支付宝付款"
        static let payCancel = "暂不付款"
        static let paySubmit = "确认付款"
        static let payNote = "付款可能扣款并启动这台洗衣机。请确认衣物已放好，实际金额以支付宝收银台为准。"
        static let amountLabel = "预计金额"
        static let modes = [LaundryStartCopy.normal, LaundryStartCopy.immediateLabel]
        static let immediateNote = "请先放好衣物、投放洗衣液并关紧门盖。付款后返回校日常，确认已付款且机器可启动后，会为本单发送一次启动指令。试用失败请到U净启动。"

        /// `program`: the one chosen for a new order; nil to pay the order already placed.
        static func sheet(_ facts: LaundryFacts, program: WasherProgram?) -> Sheet {
            if let program {
                return Sheet(title:reviewTitle, cancel:reviewCancel, submit:reviewSubmit, machine:machine(facts),
                             program:Self.program(program), note:reviewNote, asksMode:true)
            }
            return Sheet(title:payTitle, cancel:payCancel, submit:paySubmit, machine:machine(facts),
                         program:facts.recordProgram.map(Self.program) ?? facts.record?.programName, note:payNote, asksMode:false)
        }

        /// 「4 栋洗衣房 · 3号」: the store, then the machine's number.
        static func machine(_ facts: LaundryFacts) -> String {
            [facts.store, facts.machine.map { "\($0)号" } ?? "这台洗衣机"].compactMap { $0 }.joined(separator:" · ")
        }

        /// 「标准洗 · 45分钟」.
        static func program(_ program: WasherProgram) -> String { "\(program.name) · \(program.minutes)分钟" }
    }

    /// 暖橙 keeps its words; the amount is labelled and an unpaid order gets a caution line.
    enum Warm {
        static let newTitle = "下单并去支付宝付款？"
        static let payTitle = "去支付宝付款？"
        static let submit = "去付款"
        static let cancel = "先不付"
        static let amountLabel = "预计金额"
    }
}
