import SwiftUI
import Core

extension HomeView {
    // MARK: Content

    /// The school's day, as 最近 below it.
    var dateTitle: String { SchoolCalendar.dayTitle(Date()) }

    /// A balance tapped: 校园充值 (on `route`, which the sample shows as its own page), the
    /// meter picker, or the login step.
    func openBalance(_ entry: CampusTopUpEntry, as route: HomeRoute) {
        switch entry {
        case .topUp: path.append(route)
        case .bindMeter: path.append(.powerSetup)
        case .signIn: openOnboarding(from:.homeButton)
        }
    }

    @ViewBuilder func content(_ data: HomeData) -> some View {
        let now = Date()
        VStack(alignment:.leading, spacing:0) {
            dateBlock(data).id("top")
            HomeDuo(card:data.cardFigure(now:now), power:data.powerFigure(now:now),
                    cardAction:{ openBalance(CampusTopUpEntry.card(signedIn:data.signedIn), as:.card) },
                    powerAction:{ openBalance(CampusTopUpEntry.power(signedIn:data.signedIn, meterBound:data.powerBound), as:.power) })
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
                // Where 「最近」 starts, there whether it shows or not: what it measures from does not
                // move when it goes. No row fits under its header: no header and 全部 either.
                recentsAnchor(recents, all:data.signedIn)
                if recentCount(recents) > 0 {
                    recentsHeader(all:data.signedIn).padding(.top,30)
                    recentRows(recents)
                }
            }
        }
        .coordinateSpace(name:HomeView.contentSpace)
        .frame(maxWidth:600)
        .frame(maxWidth:.infinity)
    }

    func dateBlock(_ data: HomeData) -> some View {
        VStack(spacing:2) {
            // Rounded like the numbers under it; other pages keep the theme's serif title.
            Text(dateTitle).scaledFont(appTheme.titleFont.size, appTheme.titleFont.weight, design:.rounded, relativeTo:.title2).foregroundStyle(Theme.ink)
            Text([SchoolCalendar.weekday(Date()), data.dorm].compactMap { $0 }.joined(separator:" · "))
                .scaledFont(13, design:.rounded, relativeTo:.footnote).foregroundStyle(Theme.ink2)
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
        case .signIn: mark(.updateLine, [.signIn]); relogin = true
        case .account: mark(.updateLine, [.settings, .account]); campus.accountPageRequested = true; settings = true
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
            return .showering(start, caption:data.showerUnconfirmed ? ShowerDisplay.writeUnconfirmedHint : "点一下回到洗澡页")
        case .settling: return .settling
        case .stopped: return .stopped
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

    /// The whole rows that fit the screen under everything else and the header (`RecentFit`);
    /// none, and no section, when not one does. The header and every row are measured, unseen,
    /// at the current text size.
    func recentCount(_ items: [RecentItem]) -> Int {
        RecentFit.count(viewport:homeViewport, above:recentsTop, header:recentsHeaderHeight,
                        rowHeights:items.map { Double(recentHeights[$0.id] ?? 0) })
    }

    /// No height of its own: the section's top, and the hidden header and rows measured there.
    func recentsAnchor(_ items: [RecentItem], all: Bool) -> some View {
        Color.clear.frame(height:0).frame(maxWidth:.infinity)
            .onGeometryChange(for:CGFloat.self) { $0.frame(in:.named(HomeView.contentSpace)).minY } action: { recentsTop = $0 }
            .background(alignment:.top) { recentMeasure(items, all:all) }
    }

    /// The app's own showers and orders open their page; card records are plain rows.
    @ViewBuilder func recentRows(_ items: [RecentItem]) -> some View {
        let shown = items.prefix(recentCount(items))
        VStack(spacing:0) {
            ForEach(Array(shown.enumerated()), id:\.element.id) { index, item in
                VStack(spacing:0) {
                    if index > 0 { RowSeparator() }
                    if item.source == .app {
                        // A button, not a link: the page says it came from 最近.
                        let route = item.kind == .laundry ? HomeRoute.laundry : HomeRoute.shower
                        Button { mark(.recents, [route.debugPage]); path.append(route) } label: { RecentRow(item:item) }
                            .buttonStyle(RowPressStyle())
                    } else {
                        RecentRow(item:item)
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge:.top).combined(with:.opacity))
            }
        }
        .frame(maxWidth:.infinity, alignment:.top)
        .animation(Theme.spring, value:shown.map(\.id))
    }

    /// The header and every row as they would be drawn, hidden, for their heights.
    func recentMeasure(_ items: [RecentItem], all: Bool) -> some View {
        VStack(spacing:0) {
            recentsHeader(all:all).padding(.top,30)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { recentsHeaderHeight = $0 }
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
        if sample.isActive { sampleDestination(route) } else { liveDestination(route) }
    }

    /// The sample's pages: on its data, nothing read, the money and start buttons blocked.
    @ViewBuilder func sampleDestination(_ route: HomeRoute) -> some View {
        switch route {
        case .card, .records: SampleCardPage(data:data)
        case .power, .powerSetup: SamplePowerPage(data:data)
        case .shower: ShowerDetail(preview:data)
        // 常用洗衣机 binds a machine: its links are blocked in the sample (`LaundryDetail`).
        case .laundry, .washerSetup: LaundryDetail(demo:laundryDemo)
        }
    }

    @ViewBuilder func liveDestination(_ route: HomeRoute) -> some View {
        switch route {
        case .power: if campus.powerConfigured { CampusTopUpView() } else { CampusPowerSetupView() }
        case .powerSetup: CampusPowerSetupView()
        case .card: CampusTopUpView()
        // Not set up yet: hot water is bound by choosing the dorm.
        case .shower:
            // Demo records have no binding behind them.
            if shower.configured || demo != nil { ShowerDetail() } else { CampusOnboardingView() }
        case .laundry:
            LaundryDetail(demo:laundryDemo)
        // Saved or switched: back a page, or on to 洗衣 (pushed) when opened from home's unbound row.
        case .washerSetup:
            #if DEBUG
            WasherSetupView(onDone:washerSetupDone, preview:washerDemo)
            #else
            WasherSetupView(onDone:washerSetupDone)
            #endif
        case .records:
            CardRecordsView(app:recordsDemo?.app() ?? data.recentActivities, source:recordsDemo?.source ?? .school(campus))
        }
    }

    func washerSetupDone() {
        let next = WasherSetupExit.path(path, setup:.washerSetup, laundry:.laundry)
        if next.last == .laundry, path.last != .laundry { mark(.setupDone, [.laundry]) }
        path = next
    }

    // MARK: Toolbar


    @ViewBuilder var gear: some View {
        let button = Button { settings = true } label: {
            Image(systemName:"gearshape").font(.system(size:17, weight:.medium)).foregroundStyle(Theme.ink.color(appTheme))
        }.accessibilityLabel("设置")
        if #available(iOS 26, *) {
            button
        } else {
            button.frame(width:38, height:38).background(.ultraThinMaterial, in:Circle())
        }
    }
}
