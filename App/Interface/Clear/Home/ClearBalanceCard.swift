import SwiftUI
import Core

/// 电量和校园卡: the two numbers side by side (stacked with a divider at accessibility sizes),
/// 「电表 ›」 to the meter page, and the update line at the bottom. Only the links are buttons.
struct ClearBalanceCard: View {
    let data: HomeData
    /// Short screens (`HomeCompaction.tightCards`): the numbers 6 under the header row, not 16.
    var tight = false
    @Environment(ClearNavigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let now = Date()
        VStack(alignment:.leading, spacing:8) {
            VStack(alignment:.leading, spacing:tight ? 6 : 16) {
                header
                if typeSize.isAccessibilitySize {
                    VStack(alignment:.leading, spacing:16) { powerColumn(now); Divider(); cardColumn(now) }
                } else {
                    HStack(alignment:.top, spacing:16) { powerColumn(now); cardColumn(now) }
                }
            }
            if ClearUpdateLine.shows(data.updateLine) {
                ClearUpdateLine(line:data.updateLine, now:now) {
                    navigator.signInAgain(HomeUpdateLine.signInTarget(data.schoolAccount))
                }
            }
        }
        .padding(.horizontal,16).padding(.bottom,16).padding(.top,6)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }

    private var header: some View {
        HStack {
            Text("电量和校园卡").font(.headline).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength:8)
            if data.signedIn {
                Button("电表 ›") { navigator.push(.powerSetup) }
                    .font(.caption).foregroundStyle(Theme.accentText)
                    .buttonStyle(.plain)
                    .accessibilityLabel("电表")
            }
        }
        .frame(minHeight:44)
    }

    private func powerColumn(_ now: Date) -> some View {
        let figure = data.powerFigure(now:now)
        let balance = data.signedIn && data.powerBound ? data.snapshot.power.value?.leftMoney?.yuan : nil
        return ClearBalanceColumn(title:"电量", figure:figure, value:figure.value.map(Theme.kwh), unit:"度",
                                  spoken:HomeDuo.spokenPower(figure),
                                  extra:balance.map { "电费余额 " + Theme.yuan($0) },
                                  link:CampusTopUpEntry.powerLink(signedIn:data.signedIn, meterBound:data.powerBound),
                                  openLink:{ navigator.push(.power) },
                                  openMeter:{ navigator.push(.powerSetup) })
    }

    private func cardColumn(_ now: Date) -> some View {
        let figure = data.cardFigure(now:now)
        return ClearBalanceColumn(title:"校园卡", figure:figure, value:figure.value.map(CampusFormat.plainYuan), unit:"元",
                                  spoken:HomeDuo.spokenCard(figure), extra:nil,
                                  link:CampusTopUpEntry.cardLink(signedIn:data.signedIn),
                                  openLink:{ navigator.push(.card) }, openMeter:{})
    }
}
