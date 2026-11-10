import Foundation
import Core

/// The laundry page's words in 清爽: the page, the device card and the order card.
enum ClearLaundryCopy {
    /// The pay sheet's caution (shared with 暖橙's sheet).
    static let caution = "付完款机器可能马上开始洗，先把衣服放好。实际金额以支付宝里显示的为准。"

    static let title = "洗衣机"
    static let refresh = "刷新洗衣机"
    static let programsTitle = "选择程序"
    static let programsNote = "按当前价格"
    static let footnote = "先放好衣物。确认机器与程序后再下单，付款可能使设备开始运行。"
    static let confirm = "确认程序"
    /// The dock while the machine is read again.
    static let checking = "正在核对"

    static let orderHeader = "当前洗衣订单"
    static let orderPending = "正在核对预约结果"
    static let amountNote = "实际金额以支付宝收银台为准"
    static let programLabel = "洗衣程序"
    static let unpaid = "未支付"
    static let payHint = "请先放好衣物，付款可能启动洗衣机。"
    static let pay = "前往支付宝"
    static let refreshOrder = "刷新订单状态"
    static let working = "正在处理"
    static let uncertainNote = "结果未确认时请勿重复下单或付款，可在U净订单中核对。"

    /// Recent finished orders still shown above the programs (as `LaundryFacts`' window).
    private static let recentWindow: TimeInterval = 3 * 3600

    /// 「45分钟」.
    static func minutes(_ program: WasherProgram) -> String { "\(program.minutes)分钟" }

    /// 「3 号机」, or 「这台洗衣机」 before the machine is read.
    static func machine(_ facts: LaundryFacts) -> String {
        facts.snapshot.map { LaundryFormat.machine($0.deviceNo) } ?? "这台洗衣机"
    }

    /// 「已更新」 for a read under a minute old without an error, otherwise 「上次查询」.
    static func freshness(_ facts: LaundryFacts, now: Date = Date()) -> String {
        guard let snapshot = facts.snapshot else { return "暂未查询" }
        return facts.issue != nil || now.timeIntervalSince(snapshot.fetchedAt) >= 60 ? "上次查询" : "已更新"
    }

    /// 「查询于 早上7:06:09」.
    static func queried(_ date: Date) -> String {
        "查询于 " + date.formatted(date:.omitted, time:.standard)
    }

    /// The device card's state: the open order's, otherwise the machine's (「上次」 before it
    /// when the read is not fresh).
    static func deviceState(_ facts: LaundryFacts, now: Date = Date()) -> String {
        if let record = facts.record, record.inFlight {
            if let order = record.order, washing.contains(order.status.code) { return "洗衣中" }
            if record.order?.paid == true { return "待启动" }
            switch record.phase {
            case .creating, .reconcile: return "核对中"
            case .paying, .verifying: return "付款待确认"
            case .cancelling: return "取消待确认"
            default: return "已预约"
            }
        }
        guard let snapshot = facts.snapshot else { return "待查询" }
        return freshness(facts, now:now) == "已更新" ? snapshot.stateLabel : "上次" + snapshot.stateLabel
    }

    /// U净's statuses of a machine that has started.
    private static let washing: Set<String> = ["21", "22", "24", "29", "30", "35", "40"]

    /// The order card's headline: U净's status of the order.
    static func orderLabel(_ facts: LaundryFacts) -> String {
        facts.record?.order?.status.label ?? orderPending
    }

    /// The last order once it is over: its status, and whether it was paid.
    static func finished(_ facts: LaundryFacts, now: Date = Date()) -> (title: String, payment: String)? {
        guard let record = facts.record, !record.inFlight, let outcome = record.lastOutcome,
              now.timeIntervalSince(outcome.at) < recentWindow else { return nil }
        let paid = outcome.status.isDone || outcome.status.isFailedStart
        return (outcome.status.label, paid ? "已付款" : unpaid)
    }

    /// Seconds before U净 cancels an unpaid reservation, from its last read.
    static func autoCancelLeft(_ facts: LaundryFacts, now: Date = Date()) -> Int? {
        guard let record = facts.record, record.inFlight, let order = record.order, order.status.code == "10",
              let seconds = order.countDown, seconds > 0 else { return nil }
        let read = record.orderReadAt ?? record.createdAt ?? now
        return max(0, seconds - Int(now.timeIntervalSince(read)))
    }

    /// 「09:49 后自动取消」.
    static func autoCancel(left: Int) -> String {
        left > 0 ? String(format:"%02d:%02d 后自动取消", left / 60, left % 60) : "等待服务器确认预约状态"
    }

    /// 「剩余 17:19」.
    static func remaining(left: Int) -> String {
        left > 0 ? String(format:"剩余 %02d:%02d", left / 60, left % 60) : "倒计时已结束，请查看机器"
    }

    /// The order's result is not known yet: don't order or pay again.
    static func showsUncertainNote(_ facts: LaundryFacts) -> Bool {
        guard let record = facts.record else { return false }
        switch record.phase {
        case .creating, .reconcile, .cancelling: return true
        case .paying, .verifying: return record.order?.paid != true
        default: return false
        }
    }

    /// What the user must do about the order when it can't simply be paid or waited for.
    static func problemLine(_ phase: LaundryFacts.Phase) -> String? {
        switch phase {
        case .unpaid(payable:false):
            return "还没确认这笔付成功没有。先下拉刷新核对，别重复付款；确认没付成功，就取消订单重新下。"
        case .check(failedStart:true):
            return "机器没启动。去 U净 的订单里看看有没有扣款。"
        default:
            return nil
        }
    }

    /// 「3 号机 · 标准洗」: the open order.
    static func orderTitle(_ facts: LaundryFacts) -> String {
        [facts.machine.map(LaundryFormat.machine), facts.record?.programName].compactMap { $0 }.joined(separator:" · ")
    }

    /// 「3 号机 · 4 栋洗衣房」 at the top of the pay sheet.
    static func machineLine(_ facts: LaundryFacts) -> String {
        [facts.machine.map(LaundryFormat.machine) ?? "这台洗衣机", facts.store].compactMap { $0 }.joined(separator:" · ")
    }

    /// 「标准洗 · 45 分钟」 for the order's program, or its name alone.
    static func programLine(_ facts: LaundryFacts) -> String? {
        if let program = facts.recordProgram { return LaundryFormat.program(program) }
        return facts.record?.programName
    }

    /// Error lines under the content, without one the page already shows. A finished order's
    /// own line says how it ended, so its note is not repeated.
    static func issues(_ facts: LaundryFacts, shown: String?) -> [String] {
        [facts.checkoutIssue, facts.issue].compactMap { $0 }
            .reduce(into:[String]()) { list, line in if line != shown, !list.contains(line) { list.append(line) } }
    }
}
