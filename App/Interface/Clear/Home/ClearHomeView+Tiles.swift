import SwiftUI
import Core

extension ClearHomeView {
    /// 热水洗澡 and 洗衣机 side by side, stacked when they don't fit; 热水 alone, full width,
    /// while 学校洗衣机 is off.
    @ViewBuilder func tiles(_ data: HomeData) -> some View {
        if !data.laundryEnabled {
            showerTile(data)
        } else {
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.top, spacing:12) {
                    showerTile(data).frame(minWidth:145, maxHeight:.infinity, alignment:.top)
                    laundryTile(data).frame(minWidth:145, maxHeight:.infinity, alignment:.top)
                }
                .fixedSize(horizontal:false, vertical:true)
                VStack(spacing:12) { showerTile(data); laundryTile(data) }
            }
        }
    }

    func showerTile(_ data: HomeData) -> some View {
        let status = ShowerTileStatus.of(data.shower, signedIn:data.signedIn, lastMinutes:data.lastShowerMinutes,
                                         lastCost:data.lastShowerCost, issue:data.showerIssue)
        let room = ClearBalanceText.room(ShowerTileStatus.dormLine(data.dorm, signedIn:data.signedIn)) ?? ""
        return ClearServiceTile(symbol:"drop", title:"热水洗澡", detail:room, dimmed:status.dimmed,
                                action:{ openShower(status, data:data) }) {
            ClearShowerTileStatus(status:status)
        }
        .accessibilityIdentifier("clearShowerTile")
        .lookSignature()
    }

    func laundryTile(_ data: HomeData) -> some View {
        let card = HomeLaundryCard(data)
        return ClearServiceTile(symbol:"washer", title:HomeLaundryCard.clearTitle, detail:card.clearDetail(machine:data.laundryMachine),
                                action:{ openLaundry(card) }) {
            ClearLaundryTileStatus(value:card == .bound ? data.laundry.value : card.clearValue)
        }
        .accessibilityIdentifier("clearLaundryTile")
    }

    func openLaundry(_ card: HomeLaundryCard) {
        switch card.action {
        case .ujingLogin: ujingLogin = true
        case .washerSetup: navigator.push(.washerSetup)
        case .laundry: navigator.push(.laundry)
        }
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
