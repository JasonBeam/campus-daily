import SwiftUI
import Core

/// 双余额: 宿舍电量 and 校园卡 side by side (stacked with a divider at accessibility sizes, or when
/// they don't fit), 「电表设置 / 绑定电表」 to the meter page, one 「校园充值 · 微信」 link under
/// both, then any failed read in the notice colour. An expired login is a button to sign in again.
struct ClearBalanceCard: View {
    let data: HomeData
    @Environment(ClearNavigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let now = Date()
        VStack(alignment:.leading, spacing:16) {
            header
            if typeSize.isAccessibilitySize {
                powerColumn(now); Divider(); cardColumn(now)
            } else {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.top, spacing:16) { powerColumn(now).frame(minWidth:140); cardColumn(now).frame(minWidth:130) }
                    VStack(alignment:.leading, spacing:18) { powerColumn(now); Divider(); cardColumn(now) }
                }
            }
            Button { navigator.push(.card) } label: {
                Label(ClearBalanceText.topUp, systemImage:"arrow.up.forward.app")
                    .font(.subheadline).foregroundStyle(Theme.accentText)
                    .frame(maxWidth:.infinity, minHeight:44, alignment:.leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("campusRechargeEntry")
            problems
        }
        .padding(.horizontal,16).padding(.bottom,16).padding(.top,6)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }

    private var header: some View {
        HStack {
            Text(ClearBalanceText.title).font(.headline).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength:8)
            Button(ClearBalanceText.meterLink(bound:data.powerBound)) { navigator.push(.powerSetup) }
                .font(.caption).foregroundStyle(Theme.accentText)
                .buttonStyle(.plain)
                .frame(minHeight:44)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder private var problems: some View {
        if case .expired = data.updateLine {
            ClearUpdateLine(line:data.updateLine) {
                navigator.signInAgain(HomeUpdateLine.signInTarget(data.schoolAccount))
            }
        } else {
            ForEach(ClearBalanceText.issues(data.snapshot, signedIn:data.signedIn, meterBound:data.powerBound), id:\.self) { line in
                ClearNoticeText(line).font(.footnote).foregroundStyle(Theme.notice)
                    .fixedSize(horizontal:false, vertical:true)
            }
        }
    }

    private func powerColumn(_ now: Date) -> some View {
        let tile = data.snapshot.power
        let meter = data.signedIn && data.powerBound ? tile.value : nil
        return ClearBalanceColumn(title:ClearBalanceText.powerTitle,
                                  value:ClearBalanceText.number(meter?.remainingKWh), unit:"度",
                                  low:data.powerFigure(now:now).low,
                                  lines:[ClearBalanceText.powerMoney(meter), ClearBalanceText.yesterday(meter)],
                                  stamp:meter == nil ? nil : ClearBalanceText.powerStamp(tile, now:now))
    }

    private func cardColumn(_ now: Date) -> some View {
        let tile = data.snapshot.card
        let money = data.signedIn ? tile.value : nil
        return ClearBalanceColumn(title:ClearBalanceText.cardTitle,
                                  value:ClearBalanceText.number(money?.yuan), unit:"元",
                                  low:data.cardFigure(now:now).low,
                                  lines:[ClearBalanceText.cardCaption,
                                         ClearBalanceText.cardFreshness(tile, signedIn:data.signedIn,
                                                                        refreshing:data.refreshing, now:now)],
                                  stamp:money == nil ? nil : ClearBalanceText.cardStamp(tile))
            .accessibilityIdentifier("campusBalance")
    }
}
