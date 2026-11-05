import Foundation
import Core

/// A shower or laundry order that isn't finished yet: a row of 记录's 「进行中」, which opens its
/// page on 日常. The words are the ones the shower page and home's 洗衣 row already use.
struct ClearOpenItem: Identifiable, Equatable {
    enum Status: Equatable {
        /// `notice` when it waits for the user (a record to check).
        case text(String, notice: Bool)
        /// Laundry running: 「还剩 N 分钟」, ticking each minute.
        case countdown(end: Date)
    }

    let route: ClearRoute
    let title: String
    let status: Status
    var id: ClearRoute { route }

    /// The open shower first, then the open laundry order; none when nothing is open.
    static func items(_ data: HomeData) -> [ClearOpenItem] {
        [shower(data.shower), laundry(data)].compactMap { $0 }
    }

    static func shower(_ status: HomeData.Shower) -> ClearOpenItem? {
        let line: Status
        switch status {
        case .starting: line = .text(ShowerPageText.connecting, notice:false)
        case .showering: line = .text(ShowerPageText.runningLabel, notice:false)
        case .settling: line = .text(ShowerPageText.settling, notice:false)
        case .stopped: line = .text(ShowerAuthorText.homeButton, notice:false)
        case .unconfigured, .unavailable, .idle: return nil
        }
        return ClearOpenItem(route:.shower, title:"热水洗澡", status:line)
    }

    /// 「3 号机 · 标准洗」 with home's trailing value (待付款, 启动中, 还剩 N 分钟, 待核对).
    static func laundry(_ data: HomeData) -> ClearOpenItem? {
        guard data.laundryEnabled else { return nil }
        let line: Status
        switch data.laundry {
        case .unpaid, .starting, .running, .unresolved:
            switch data.laundry.value {
            case .word(let word)?: line = .text(word, notice:false)
            case .accentWord(let word)?: line = .text(word, notice:true)
            case .countdown(let end)?: line = .countdown(end:end)
            default: return nil
            }
        case .unknown, .idle, .done, .inUse, .unavailable: return nil
        }
        return ClearOpenItem(route:.laundry, title:laundryTitle(data), status:line)
    }

    private static func laundryTitle(_ data: HomeData) -> String {
        let order = data.appActivities.first { if case .laundry = $0.kind { return true }; return false }
        var program: String?
        if case .running(let name, _) = data.laundry { program = name }
        else if case .laundry(let name)? = order?.kind { program = name }
        let machine = data.laundryBound ? data.laundryMachine.map(LaundryFormat.machine) : order?.detail
        let parts = [machine, program].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "洗衣" : parts.joined(separator:" · ")
    }
}
