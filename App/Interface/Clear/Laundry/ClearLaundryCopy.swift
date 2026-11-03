import Foundation
import Core

/// The laundry page's words in 清爽: the same strings 暖橙's `LaundryDetail` shows, picked for
/// 清爽's cards instead of its hero sentence.
enum ClearLaundryCopy {
    static let caution = "付完款机器可能马上开始洗，先把衣服放好。实际金额以支付宝里显示的为准。"

    /// 「3 号机」, or 「这台洗衣机」 before the machine is read.
    static func machine(_ facts: LaundryFacts) -> String {
        facts.snapshot.map { LaundryFormat.machine($0.deviceNo) } ?? "这台洗衣机"
    }

    /// The device card's state: the order's while one is open, otherwise the machine's
    /// (as `LaundryModel.deviceStateText`).
    static func deviceState(_ facts: LaundryFacts) -> String {
        if let record = facts.record, record.inFlight { return LaundryDisplay(record).title }
        return facts.snapshot?.stateLabel ?? "待查询"
    }

    /// The machine can't take an order: its state is a problem, not news.
    static func isProblem(_ phase: LaundryFacts.Phase) -> Bool {
        switch phase {
        case .inUse, .unavailable: return true
        default: return false
        }
    }

    /// Under the device card when the machine is busy or unavailable.
    static func unavailableLine(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> String? {
        let machine = machine(facts)
        switch phase {
        case .inUse: return machine + "有人在用。换一台，或者等会儿再来。"
        case .unavailable(let kind):
            let word = kind == .offline ? "离线了。" : kind == .broken ? "坏了。" : "停用了。"
            return machine + word + "换一台试试。"
        default: return nil
        }
    }

    /// The disabled dock's label while the machine can't take an order.
    static func unavailableTitle(_ phase: LaundryFacts.Phase) -> String {
        switch phase {
        case .unavailable(.offline): return "机器离线"
        case .unavailable(.broken): return "机器故障"
        case .unavailable(.disabled): return "机器停用"
        default: return "有人在用"
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

    /// The order card's sentence and whether it is a problem.
    static func orderCaption(_ facts: LaundryFacts, phase: LaundryFacts.Phase, notify: Bool) -> (text: String, problem: Bool)? {
        switch phase {
        case .unpaid(let payable):
            if payable {
                return (programLine(facts).map { $0 + "。付完款机器可能马上开始洗。" } ?? "付完款机器可能马上开始洗。", false)
            }
            return ("还没确认这笔付成功没有。先下拉刷新核对，别重复付款；确认没付成功，就取消订单重新下。", true)
        case .starting:
            return ("已付款，等机器启动。", false)
        case .running(let end):
            let program = facts.record?.programName ?? "洗衣"
            return (program + " · " + CampusFormat.clock(end) + " 洗完。" + (notify ? "洗好了会通知你。" : ""), false)
        case .check(let failedStart):
            if failedStart { return ("机器没启动。去 U净 的订单里看看有没有扣款。", true) }
            return ("还没确认订单结果。先下拉刷新，别重复下单或付款。", true)
        default:
            return nil
        }
    }

    /// Error lines under the content, without one the page already shows.
    static func issues(_ facts: LaundryFacts, shown: String?) -> [String] {
        [facts.checkoutIssue, facts.issue, facts.outcomeNote()].compactMap { $0 }
            .reduce(into:[String]()) { list, line in if line != shown, !list.contains(line) { list.append(line) } }
    }
}
