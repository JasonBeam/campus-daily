import SwiftUI
import Core

extension HomeView {
    // MARK: Content

    /// The school's day, as 最近 below it.
    var dateTitle: String { SchoolCalendar.dayTitle(Date()) }

    @ViewBuilder func content(_ data: HomeData) -> some View {
        let now = Date()
        VStack(alignment:.leading, spacing:0) {
            dateBlock(data).id("top")
            HomeDuo(card:data.cardFigure(now:now), power:data.powerFigure(now:now),
                    cardAction:{ data.signedIn ? path.append(.card) : openOnboarding() },
                    powerAction:{ data.signedIn ? path.append(data.powerBound ? .power : .powerSetup) : openOnboarding() })
                .padding(.top,28)
            HomeUpdateLineView(line:data.updateLine, now:now) { signInAgain(data) }
                .padding(.top,16).padding(.horizontal,24)
            showerSection(data).padding(.top,28)
            if data.laundryEnabled {
                HomeSectionHeader(text:"洗衣").padding(.top,30)
                rowLink(data.laundryBound ? .laundry : .washerSetup, label:laundryLabel(data)) { laundryRow(data) }
            }
            let recents = data.recents
            if !recents.isEmpty {
                recentsHeader(all:data.signedIn).padding(.top,30)
                recentRows(recents)
            }
        }
        .coordinateSpace(name:HomeView.contentSpace)
        .frame(maxWidth:600)
        .frame(maxWidth:.infinity)
    }

    func dateBlock(_ data: HomeData) -> some View {
        VStack(spacing:2) {
            Text(dateTitle).scaledFont(24, .semibold, design:.serif, relativeTo:.title2).foregroundStyle(Theme.ink)
            Text([SchoolCalendar.weekday(Date()), data.dorm].compactMap { $0 }.joined(separator:" · "))
                .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth:.infinity)
        // Pull the date up into the nav-bar row so 「10月28日」 is centred on the gear; at
        // accessibility sizes the taller date would run under the bar, so it stays below it.
        .padding(.top,typeSize.isAccessibilitySize ? 0 : dateLift)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel([dateTitle, SchoolCalendar.weekday(Date()), data.dorm].compactMap { $0 }.joined(separator:"，"))
        .accessibilityAddTraits(.isHeader)
        .onGeometryChange(for:Bool.self) { $0.frame(in:.global).maxY < 64 } action: { scrolledPastDate = $0 }
    }

    // MARK: Shower

    /// The shower button, or a plain row when hot water can't be used here.
    @ViewBuilder func showerSection(_ data: HomeData) -> some View {
        if let kind = showerKind(data) {
            HomeShowerButton(kind:kind) { tap(kind) }
        } else {
            VStack(spacing:0) {
                Hairline()
                rowLink(.shower, label:"热水，" + showerUnavailableReason(data)) {
                    StatusRow(symbol:"shower", title:"热水", subtitle:showerUnavailableReason(data), dimmed:true)
                }
                Hairline()
            }
        }
    }

    /// The expired-login line: the sign-in form, or Settings › 学校账号 when the saved password
    /// is paused there.
    func signInAgain(_ data: HomeData) {
        switch HomeUpdateLine.signInTarget(data.schoolAccount) {
        case .signIn: relogin = true
        case .account: campus.accountPageRequested = true; settings = true
        }
    }

    func showerKind(_ data: HomeData) -> HomeShowerButton.Kind? {
        if data.shower.asksForSchoolSignIn(signedIn:data.signedIn) { return .signIn }
        switch data.shower {
        case .unconfigured, .unavailable: return nil
        case .idle:
            if let issue = data.showerIssue { return .start(caption:issue) }
            let last = data.lastShowerMinutes.map { "上次 \($0) 分钟" + (data.lastShowerCost.map { " · " + Theme.yuan($0) } ?? "") }
            return .start(caption:last)
        case .starting: return .starting
        case .showering(let start):
            return .showering(start, caption:data.showerUnconfirmed ? ShowerCopy.writeUnconfirmed : "点一下回到洗澡页")
        case .settling: return .settling
        case .unresolved: return .review
        case .needsCheck: return .check
        }
    }

    func showerUnavailableReason(_ data: HomeData) -> String {
        switch data.shower {
        case .unavailable(let reason): return reason
        default: return "先在设置里选好宿舍"
        }
    }

    // MARK: Rows

    func rowLink(_ route: HomeRoute, label: String, @ViewBuilder row: () -> some View) -> some View {
        NavigationLink(value:route) { row() }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    func laundryTitle(_ data: HomeData) -> String {
        guard data.laundryBound, let machine = data.laundryMachine else { return "洗衣" }
        return "\(machine) 号机"
    }
    func laundryRow(_ data: HomeData) -> some View {
        StatusRow(symbol:"washer", title:laundryTitle(data),
                  subtitle:data.laundryBound ? data.laundry.subtitle : "扫机身上的码来绑定",
                  value:data.laundryBound ? data.laundry.value : nil)
    }
    func laundryLabel(_ data: HomeData) -> String {
        guard data.laundryBound else { return "洗衣，扫机身上的码来绑定" }
        var subtitle = data.laundry.subtitle
        if case .running(let program, let end) = data.laundry { subtitle = program + "，" + LaundryFormat.spokenClock(end) + "洗完" }
        return ["洗衣", laundryTitle(data), data.laundry.spokenValue(), subtitle].compactMap { $0 }.joined(separator:"，")
    }

    /// 「最近」 and, while signed in, 「全部 ›」 to 校园卡记录.
    func recentsHeader(all: Bool) -> some View {
        HStack(alignment:.firstTextBaseline) {
            Text("最近").scaledFont(13, .semibold, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength:8)
            if all {
                NavigationLink(value:HomeRoute.records) {
                    HStack(alignment:.firstTextBaseline, spacing:3) {
                        Text("全部").scaledFont(13, .medium, relativeTo:.footnote)
                        Image(systemName:"chevron.right").scaledFont(11, .semibold, relativeTo:.footnote)
                    }
                    .foregroundStyle(Theme.accentText)
                    // 44 pt to tap without moving 「最近」.
                    .padding(.vertical,12).padding(.leading,8)
                    .contentShape(Rectangle())
                    .padding(.vertical,-12)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("全部校园卡记录")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("allRecords")
            }
        }
        .padding(.horizontal,24).padding(.bottom,4)
    }

    /// The whole rows that fit the screen under everything else (`RecentFit`): home never
    /// scrolls. Every row given is measured, unseen, at the current text size.
    func recentCount(_ items: [RecentItem]) -> Int {
        RecentFit.count(viewport:homeViewport, above:recentsTop,
                        rowHeights:items.map { Double(recentHeights[$0.id] ?? 0) })
    }

    /// The app's own showers and orders open their page; card records are plain rows.
    @ViewBuilder func recentRows(_ items: [RecentItem]) -> some View {
        let shown = items.prefix(recentCount(items))
        VStack(spacing:0) {
            ForEach(Array(shown.enumerated()), id:\.element.id) { index, item in
                VStack(spacing:0) {
                    if index > 0 { RowSeparator() }
                    if item.source == .app {
                        NavigationLink(value:item.kind == .laundry ? HomeRoute.laundry : HomeRoute.shower) { RecentRow(item:item) }
                            .buttonStyle(RowPressStyle())
                    } else {
                        RecentRow(item:item)
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge:.top).combined(with:.opacity))
            }
        }
        .frame(maxWidth:.infinity, alignment:.top)
        .background(alignment:.top) { recentMeasure(items) }
        .onGeometryChange(for:CGFloat.self) { $0.frame(in:.named(HomeView.contentSpace)).minY } action: { recentsTop = $0 }
        .animation(Theme.spring, value:shown.map(\.id))
    }

    /// Every row as it would be drawn, hidden, for its height.
    func recentMeasure(_ items: [RecentItem]) -> some View {
        VStack(spacing:0) {
            ForEach(Array(items.enumerated()), id:\.element.id) { index, item in
                VStack(spacing:0) {
                    if index > 0 { RowSeparator() }
                    RecentRow(item:item)
                }
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { recentHeights[item.id] = $0 }
            }
        }
        .fixedSize(horizontal:false, vertical:true)
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder func destination(_ route: HomeRoute) -> some View {
        switch route {
        case .power: if campus.powerConfigured { CampusRechargeView(kind:.power) } else { CampusPowerSetupView() }
        case .powerSetup: CampusPowerSetupView()
        case .card:
            #if DEBUG
            CampusRechargeView(kind:.card, demoBlocked:rechargeBlockedDemo)
            #else
            CampusRechargeView(kind:.card)
            #endif
        // Not set up yet: hot water is bound by choosing the dorm.
        case .shower:
            #if DEBUG
            // Demo records have no binding behind them.
            if shower.configured || demo != nil { ShowerDetail() } else { CampusOnboardingView() }
            #else
            if shower.configured { ShowerDetail() } else { CampusOnboardingView() }
            #endif
        case .laundry:
            #if DEBUG
            LaundryDetail(demo:laundryDemo)
            #else
            LaundryDetail()
            #endif
        case .washerSetup: WasherSetupView()
        case .records:
            #if DEBUG
            CardRecordsView(app:recordsDemo?.app() ?? data.recentActivities, source:recordsDemo?.source ?? .live)
            #else
            CardRecordsView(app:data.recentActivities, source:.live)
            #endif
        }
    }

    // MARK: Toolbar


    @ViewBuilder var gear: some View {
        let button = Button { settings = true } label: {
            Image(systemName:"gearshape").font(.system(size:17, weight:.medium)).foregroundStyle(Theme.ink)
        }.accessibilityLabel("设置")
        if #available(iOS 26, *) {
            button
        } else {
            button.frame(width:38, height:38).background(.ultraThinMaterial, in:Circle())
        }
    }
}
