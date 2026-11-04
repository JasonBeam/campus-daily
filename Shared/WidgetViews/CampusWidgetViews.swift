import SwiftUI
import WidgetKit
import Core

/// What the 「校日常」 widget shows. Built from the shared snapshot and the saved
/// account; compiled into the widget and the app (DEBUG preview only).
struct CampusWidgetModel: Sendable {
    /// fresh / stale / expired / never, from `WidgetStatus.freshness` (Core), never decided here.
    var state: WidgetFreshness
    var remainingKWh: Decimal?
    var balance: Decimal?
    /// 「昨天用了 X 度」: only when the meter reported it.
    var yesterdayKWh: Decimal?
    /// 「电费余额 ¥X」: the meter's money balance, only when a meter reading exists.
    var powerBalance: Decimal?
    /// The last successful update (the stored `fetchedAt`).
    var updated: Date?
    /// When this face is drawn (the timeline entry's date): the footer says 「昨天」 or the date
    /// relative to it.
    var now = Date()
    /// The user's reminder lines (Settings › 提醒), shared through the keychain; default 10 度 / 20 元.
    var lines = ReminderLines()

    /// The face is drawn as grey bars (`redacted`): the gallery's sample, or no readable data yet.
    var placeholder = false

    static let never = CampusWidgetModel(state:.never)
    /// Sample shapes only, always drawn redacted: no number on it is anyone's, and none is shown.
    static let placeholderFace: CampusWidgetModel = {
        var model = CampusWidgetModel(state:.fresh, remainingKWh:Decimal(string:"42.6"), balance:Decimal(string:"86.50"),
                                      yesterdayKWh:Decimal(string:"5.1"), powerBalance:Decimal(string:"23.40"), updated:Date())
        model.placeholder = true
        return model
    }()

    init(state: WidgetFreshness, remainingKWh: Decimal? = nil, balance: Decimal? = nil, yesterdayKWh: Decimal? = nil,
         powerBalance: Decimal? = nil, updated: Date? = nil, now: Date = Date()) {
        self.state = state; self.remainingKWh = remainingKWh; self.balance = balance
        self.yesterdayKWh = yesterdayKWh; self.powerBalance = powerBalance; self.updated = updated; self.now = now
        tap = state.opensLogin ? .login : .home
    }

    /// A failed read keeps the last numbers and their time (the snapshot keeps them).
    init(snapshot: HomeSnapshot?, account: SchoolAccount?, now: Date) {
        let state = WidgetStatus.freshness(snapshot:snapshot, account:account, now:now)
        guard let snapshot, state != .never else { self = .never; return }
        let meter = snapshot.power.value
        self.init(state:state, remainingKWh:meter?.remainingKWh, balance:snapshot.card.value?.yuan,
                  yesterdayKWh:meter?.dailyUseKWh, powerBalance:meter?.leftMoney?.yuan,
                  updated:WidgetStatus.shownUpdated(snapshot), now:now)
        tap = WidgetStatus.tap(snapshot:snapshot, account:account, now:now)
    }

    /// 「22:10 更新」/「昨天 22:10 更新」/「10月29日 22:10 更新」.
    var updatedText: String? { updated.map { UpdateTimeText.widgetUpdated($0, now:now, calendar:.current) } }
    /// The time before 「 · 打开 App 更新」 on the stale face: medium has room for the day and the
    /// clock, small shows the clock today and the day alone otherwise.
    func staleStamp(medium: Bool) -> String? {
        updated.map { medium ? UpdateTimeText.stamp($0, now:now, calendar:.current)
                             : UpdateTimeText.dayOrClock($0, now:now, calendar:.current) }
    }

    /// Signed in but no number read yet (and not expired): 「打开 App 更新」.
    var waitingForFirstRead: Bool {
        state != .never && state != .expired && remainingKWh == nil && balance == nil
    }

    /// Red only for low electricity, and not on numbers an expired login greys out.
    var powerLow: Bool { state != .expired && (remainingKWh.map { $0 < lines.power } ?? false) }

    /// From `WidgetStatus.tap` (Core): login step, Settings › 学校账号 or home.
    var tap: WidgetTap = .home
    var url: URL { tap.url }

    func accessibilityLabel(medium: Bool) -> String {
        if placeholder { return "校日常" }
        switch state {
        case .never: return "登录后显示余额和电量，打开 App，登录学校账号"
        case .expired: return "登录过期了，打开 App 重新登录"
        case .fresh, .stale: break
        }
        guard !waitingForFirstRead else { return "打开 App 更新" }
        var parts: [String] = []
        if let remainingKWh { parts.append("宿舍电量 \(CampusFormat.kwh(remainingKWh)) 度") }
        if let balance { parts.append("校园卡余额 \(CampusFormat.plainYuan(balance)) 元") }
        if medium, let powerBalance { parts.append("电费余额 \(CampusFormat.plainYuan(powerBalance)) 元") }
        if let updatedText { parts.append(updatedText) }
        if state == .stale { parts.append("打开 App 更新") }
        return parts.joined(separator:"，")
    }
}

/// Widget content without the container background (the widget adds `.containerBackground`,
/// the DEBUG preview draws its own rounded tile).
struct CampusWidgetFace: View {
    let model: CampusWidgetModel
    var medium = false
    /// The app's theme when the entry was made.
    var theme: AppTheme = .standard
    private var P: CampusWidgetPalette { .of(theme) }
    var body: some View {
        Group {
            if model.state == .never { never }
            else if model.waitingForFirstRead { firstRead }
            else if medium { mediumBody }
            else if model.state == .expired { smallExpired }
            else { smallBody }
        }
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
        .typesettingLanguage(Locale.Language(identifier:"zh-Hans"))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(model.accessibilityLabel(medium:medium))
    }

    private var expired: Bool { model.state == .expired }

    // MARK: Never signed in, first read

    private var never: some View {
        // The droplet fills 44 of the glyph's 64-pt box across: medium draws it 44 pt wide;
        // small keeps its 28-pt box.
        let size: CGFloat = medium ? 64 : 28
        return VStack(alignment:.leading, spacing:10) {
            // The droplet body starts 10/64 into its box: pull it back so it sits on the 16pt margin like the text.
            MascotGlyph(size:size, color:P.accent).padding(.leading, -size * 10 / 64)
            VStack(alignment:.leading, spacing:4) {
                Text("登录后显示余额和电量").font(.system(size:15, weight:.semibold)).foregroundStyle(P.ink)
                    .fixedSize(horizontal:false, vertical:true)
                if medium {
                    Text("打开 App，登录学校账号").font(.system(size:13)).foregroundStyle(P.ink2).lineLimit(1)
                }
            }
        }
    }

    private var firstRead: some View {
        Text("打开 App 更新")
            .font(.system(size:17, weight:.semibold)).foregroundStyle(P.ink)
            .fixedSize(horizontal:false, vertical:true)
    }

    // MARK: Small

    private var smallBody: some View {
        VStack(alignment:.leading, spacing:8) {
            smallStack(symbol:"bolt", number:model.remainingKWh.map(CampusFormat.kwh), unit:"度", low:model.powerLow, label:"宿舍电量")
            smallStack(symbol:"creditcard", number:model.balance.map(CampusFormat.yuan), unit:nil, low:false, label:"校园卡")
            Spacer(minLength:0)
            footer
        }
    }
    /// The card line only, then what to do.
    private var smallExpired: some View {
        VStack(alignment:.leading, spacing:8) {
            smallStack(symbol:"creditcard", number:model.balance.map(CampusFormat.yuan), unit:nil, low:false, label:"校园卡")
            Spacer(minLength:0)
            VStack(alignment:.leading, spacing:2) {
                Text("登录过期了").font(.system(size:15, weight:.semibold)).foregroundStyle(P.ink).lineLimit(1)
                Text("打开 App 重新登录").font(.system(size:13)).foregroundStyle(P.ink2).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
    private func smallStack(symbol: String, number: String?, unit: String?, low: Bool, label: String) -> some View {
        VStack(alignment:.leading, spacing:4) {
            HStack(alignment:.firstTextBaseline, spacing:4) {
                icon(symbol, size:15).frame(width:22, alignment:.leading)
                HStack(alignment:.firstTextBaseline, spacing:3) {
                    numberText(number, size:30, low:low)
                    if let unit, number != nil { Text(unit).font(.system(size:14, weight:.medium)).foregroundStyle(P.ink2) }
                }
            }
            Text(label).font(.system(size:13, weight:.medium)).foregroundStyle(P.ink2).padding(.leading,26)
        }
    }

    // MARK: Medium

    private var mediumBody: some View {
        VStack(alignment:.leading, spacing:6) {
            HStack(alignment:.top, spacing:0) {
                VStack(alignment:.leading, spacing:0) {
                    header(symbol:"bolt", "宿舍电量")
                    HStack(alignment:.firstTextBaseline, spacing:3) {
                        numberText(model.remainingKWh.map(CampusFormat.kwh), size:34, low:model.powerLow)
                        if model.remainingKWh != nil { Text("度").font(.system(size:15, weight:.medium)).foregroundStyle(P.ink2) }
                    }.padding(.top,8)
                    VStack(alignment:.leading, spacing:2) {
                        if let yesterday = model.yesterdayKWh { mini("昨天用了", CampusFormat.kwh(yesterday), " 度") }
                        if let money = model.powerBalance { mini("电费余额", CampusFormat.yuan(money), "") }
                    }.padding(.top,4)
                    Spacer(minLength:0)
                }
                .padding(.trailing,12)
                .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
                Rectangle().fill(P.separator).frame(width:0.5)
                VStack(alignment:.leading, spacing:0) {
                    header(symbol:"creditcard", "校园卡")
                    numberText(model.balance.map(CampusFormat.yuan), size:34, low:false).padding(.top,8)
                    if model.balance != nil {
                        Text("余额").font(.system(size:13)).foregroundStyle(P.ink2).padding(.top,4)
                    }
                    Spacer(minLength:0)
                }
                .padding(.leading,16)
                .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
            }
            footer
        }
    }
    private func header(symbol: String, _ text: String) -> some View {
        HStack(spacing:4) {
            icon(symbol, size:13)
            Text(text).font(.system(size:13, weight:.semibold)).foregroundStyle(P.ink2).lineLimit(1)
        }
    }
    /// 13 ink2, the number inside in ink medium (ink3 when expired).
    private func mini(_ lead: String, _ number: String, _ tail: String) -> some View {
        let value = Text(number).fontWeight(.medium).foregroundStyle(expired ? P.ink3 : P.ink)
        return Text("\(lead) \(value)\(tail)").font(.system(size:13)).foregroundStyle(P.ink2).lineLimit(1)
    }

    // MARK: Shared pieces

    /// The line icons of home (creditcard, bolt): outline, regular, in the theme's icon colour in
    /// every state; a low value turns only the number red.
    private func icon(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName:symbol).symbolRenderingMode(.monochrome)
            .font(.system(size:size, weight:.regular)).foregroundStyle(P.icon)
            .accessibilityHidden(true)
    }

    private func numberText(_ number: String?, size: CGFloat, low: Bool) -> some View {
        Text(number ?? "—")
            .font(.system(size:size, weight:.semibold, design:P.numberDesign)).monospacedDigit().tracking(-0.4)
            .foregroundStyle(number == nil ? P.ink2 : expired ? P.ink3 : low ? P.redLarge : P.ink)
            .lineLimit(1).minimumScaleFactor(0.6)
            .widgetAccentable()
    }

    /// fresh: 「10:32 更新」 ink2; stale: 「昨天 8:10 · 打开 App 更新」 (small: 「昨天 · 打开 App 更新」) (time ink2, action accentText);
    /// expired (medium): 「登录过期了 · 打开 App 重新登录」 (the lead in notice).
    @ViewBuilder private var footer: some View {
        switch model.state {
        case .expired:
            let lead = Text("登录过期了").fontWeight(.semibold).foregroundStyle(P.notice)
            let tail = Text(" · 打开 App 重新登录").foregroundStyle(P.ink2)
            Text("\(lead)\(tail)").font(.system(size:11)).lineLimit(1).minimumScaleFactor(0.8)
        case .stale:
            let time = Text(model.staleStamp(medium:medium).map { $0 + " · " } ?? "").foregroundStyle(P.ink2)
            let action = Text("打开 App 更新").fontWeight(.semibold).foregroundStyle(P.accentText)
            // One line at full size: the small face's date-only stamp is short enough not to shrink.
            Text("\(time)\(action)").font(.system(size:11)).monospacedDigit().lineLimit(1)
        case .fresh, .never:
            if let updated = model.updatedText {
                Text(updated).font(.system(size:11)).monospacedDigit().foregroundStyle(P.ink2).lineLimit(1)
            }
        }
    }
}
