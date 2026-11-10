import Foundation
import Core

/// The shower that isn't finished yet: 订单's 「当前热水记录」 row, which opens its page on 日常.
/// The words are the ones the shower page already uses.
struct ClearOpenItem: Identifiable, Equatable {
    enum Status: Equatable {
        /// `notice` when it waits for the user (a record to check).
        case text(String, notice: Bool)
    }

    let route: ClearRoute
    let title: String
    let status: Status
    var id: ClearRoute { route }

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
}
