import SwiftUI
import Core

extension ClearHomeView {
    /// 热水 and 洗衣 side by side (text wraps), stacked at accessibility sizes; 热水 alone, full
    /// width, while 学校洗衣机 is off. `tight`: `HomeCompaction.tightCards`.
    @ViewBuilder func tiles(_ data: HomeData, tight: Bool) -> some View {
        if !data.laundryEnabled {
            showerTile(data, tight:tight)
        } else if typeSize.isAccessibilitySize {
            VStack(spacing:12) { showerTile(data, tight:tight); laundryTile(data, tight:tight) }
        } else {
            HStack(alignment:.top, spacing:12) {
                showerTile(data, tight:tight).frame(maxHeight:.infinity, alignment:.top)
                laundryTile(data, tight:tight).frame(maxHeight:.infinity, alignment:.top)
            }
            .fixedSize(horizontal:false, vertical:true)
        }
    }

    func showerTile(_ data: HomeData, tight: Bool) -> some View {
        let status = ShowerTileStatus.of(data.shower, signedIn:data.signedIn, lastMinutes:data.lastShowerMinutes,
                                         lastCost:data.lastShowerCost, issue:data.showerIssue)
        return ClearServiceTile(symbol:"drop", title:"热水洗澡", detail:ShowerTileStatus.dormLine(data.dorm, signedIn:data.signedIn) ?? "宿舍热水", dimmed:status.dimmed, tight:tight,
                                action:{ openShower(status, data:data) }) {
            ClearShowerTileStatus(status:status)
        }
        .accessibilityIdentifier("clearShowerTile")
    }

    func laundryTile(_ data: HomeData, tight: Bool) -> some View {
        let detail = data.laundryBound
            ? [data.laundryMachine.map { "\($0) 号机" }, data.laundry.subtitle].compactMap { $0 }.joined(separator:" · ")
            : "扫机身上的码来绑定"
        return ClearServiceTile(symbol:"washer", title:"洗衣", detail:detail, tight:tight,
                                action:{ navigator.push(data.laundryBound ? .laundry : .washerSetup) }) {
            if data.laundryBound { ClearLaundryTileStatus(value:data.laundry.value) }
        }
        .accessibilityIdentifier("clearLaundryTile")
    }

    /// The 热水 page: as it stands while a shower is going on (the model brings it up), otherwise
    /// pushed; signed out, the first-run checklist.
    func openShower(_ status: ShowerTileStatus, data: HomeData) {
        if status.opensSetup { navigator.openSetup(from:.homeButton); return }
        // Demo states have no shower behind them: the page as it is.
        if navigator.demo != nil { navigator.push(.shower); return }
        switch data.shower {
        case .starting, .showering, .settling, .stopped:
            // The tile was tapped: the page the model raises next is this tap's (and its
            // 上一次洗好了 face).
            var pages: Set<DebugPage> = [.showerPage]
            if case .stopped = data.shower { pages.insert(.showerStopped) }
            navigator.mark(.homeButton, pages:pages)
            shower.pageEvent(.reopen)
            if !shower.page.presented { navigator.push(.shower) }
        case .idle, .unconfigured, .unavailable:
            navigator.push(.shower)
        }
    }
}
