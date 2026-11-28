//
//  HomeView+Demo.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import SwiftUI
import UserNotifications
import Core

#if DEBUG
extension HomeView {
    /// Also called from inside the onboarding cover: while a full-screen cover is up,
    /// the URL is delivered to the cover's hierarchy instead of the home view.
    func handleDemo(_ url: URL) {
            // No sample page opens a link.
            guard !sample.isActive else { return }
            // A synthetic running record in this root's own (live) hot-water vault.
            if url.host == "demo", url.path == "/seed/shower-running" { shower.demoSeedRunningRecord(); return }
            // campusdaily://demo/seed/debt-on: the debt start setting on (stored, as the phrase would);
            // /seed/debt-off-unstored: on, and every turn-off of it reads as not stored.
            if url.host == "demo", ["/seed/debt-on", "/seed/debt-off-unstored"].contains(url.path) {
                DebtShowerVisit.demoTurnOffUnstored = url.path == "/seed/debt-off-unstored"
                shower.setAllowsDebt(true)
                return
            }
            if let kind = notifyDemo(url) { Task { await reminders.demoNotify(kind) }; return }
            // campusdaily://demo/theme/<warm|clear>: what 主题 would pick, keeping the screen shown.
            if url.host == "demo", url.pathComponents.dropFirst().first == "theme",
               let theme = AppTheme(rawValue:url.lastPathComponent) { themeStore.select(theme); return }
            if let page = WidgetPreview.handle(url) { activityPreview = nil; widgetPreview = page; return }
            widgetPreview = nil
            if let kind = LaundryActivityPreview.handle(url) { activityPreview = kind; return }
            activityPreview = nil
            if LaundryActivityController.handleDemo(url) { return }
            ShowerPageDemo.apply(nil, to:shower)
            if url.host == "demo", url.lastPathComponent == "login-loading" {
                onboarding = nil; settings = false; path = []
                demo = HomeDemo.normal.content().0
                Task { try? await Task.sleep(for:.milliseconds(400)); loginDemo = true }
                return
            }
            if let onboard = OnboardingDemo.handle(url) {
                settings = false; path = []
                onboarding = OnboardingRequest(step:onboard.0, preview:onboard.1)
                return
            }
            if let laundryPage = LaundryDemo.handle(url) {
                onboarding = nil
                demo = HomeDemo.normal.content().0
                laundryDemo = laundryPage; washerDemo = nil
                panel = laundryPage.panel
                // Fresh push so the page's @State starts from this demo.
                freshPush(.laundry)
                return
            }
            if let washer = WasherSetupDemo.handle(url) {
                // 常用洗衣机 over the home demo; a fresh push so the page starts from this demo.
                onboarding = nil; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                washerDemo = washer
                freshPush(.washerSetup)
                return
            }
            // campusdaily://demo/stats/<state>: the records list demo, its stats on that demo state.
            SpendStatsDemo.current = SpendStatsDemo.handle(url)
            let statsRecords: RecordsDemo? = SpendStatsDemo.current.map { $0 == .refreshFailedOld ? .staleOld : .list }
            if let records = statsRecords ?? RecordsDemo.handle(url) {
                // 校园卡记录 over the home demo; a fresh push so the page starts from this demo.
                onboarding = nil; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                recordsDemo = records; washerDemo = nil
                freshPush(.records)
                return
            }
            if url.host == "demo", url.lastPathComponent.hasPrefix("account-switched") || url.lastPathComponent.hasPrefix("account-unconfirmed") {
                // Account-switch alert over the home demo (「account-unconfirmed」: the login couldn't
                // tell the previous person); 「-water」 adds the hot-water line and button.
                onboarding = nil; settings = false; path = []
                demo = HomeDemo.normal.content().0
                campus.switchNotice = AccountSwitchNotice(previousPersonUnconfirmed:url.lastPathComponent.hasPrefix("account-unconfirmed"),
                                                          hotWaterCleared:url.lastPathComponent.hasSuffix("-water"))
                return
            }
            if url.host == "demo", ["meter-stopped", "meter-stopped-finding", "meter-stopped-slow", "meter-ask", "meter-ask-mixed", "meter-unfinished"].contains(url.lastPathComponent) {
                // The meter page where the lookup stopped (synthetic): as is / looking again / slow school /
                // two apartments with the dorm's room (or one, the other halted) / one of them not read.
                onboarding = nil; panel = nil; laundryDemo = nil
                demo = HomeDemo.noMeter.content().0
                campus.demoMeterStop(running:url.lastPathComponent.hasSuffix("finding"), slow:url.lastPathComponent.hasSuffix("slow"),
                                     ask:url.lastPathComponent == "meter-ask", unfinished:url.lastPathComponent == "meter-unfinished",
                                     mixed:url.lastPathComponent == "meter-ask-mixed")
                freshPush(.powerSetup)
                return
            }
            if url.host == "demo", url.lastPathComponent == "permission" {
                // Pre-permission sheet over the home demo, whatever the real authorization is.
                onboarding = nil; settings = false; path = []
                demo = HomeDemo.normal.content().0
                reminders.prompt = .app
                return
            }
            if url.host == "demo", url.lastPathComponent == "permission-home" {
                // Home demo, then the first-home-read trigger: the sheet appears once home is clear.
                onboarding = nil; settings = false; path = []; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                reminders.demoHomeRead()
                return
            }
            if url.host == "demo", url.lastPathComponent == "sh-from-settings" {
                // Settings up, then a start: the sheet closes and the page comes up.
                onboarding = nil; path = []; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                settings = true
                Task {
                    try? await Task.sleep(for:.seconds(1.5))
                    shower.showDemoPage(ShowerPageDemo.record("sh-connect"))
                }
                return
            }
            if url.host == "demo", url.lastPathComponent == "sh-under-onboarding" {
                // The first-run guide up, then a shower ended from the lock screen: the guide
                // closes and the result comes up.
                path = []; panel = nil; laundryDemo = nil; settings = false
                demo = HomeDemo.normal.content().0
                onboarding = OnboardingRequest(step:.login, preview:OnboardingView.Preview(dorm:"3 栋 108"))
                Task {
                    try? await Task.sleep(for:.seconds(1.5))
                    shower.showDemoPage(ShowerPageDemo.record("sh-done"))
                }
                return
            }
            if url.host == "demo", let record = ShowerPageDemo.record(url.lastPathComponent) {
                // The shower page over the home demo, on a synthetic record (nothing connects).
                onboarding = nil; settings = false; path = []; panel = nil; laundryDemo = nil
                demo = HomeDemo.normal.content().0
                // Collapsed while water runs, home shows the showering button, as it would live.
                if record.phase == .running, let start = record.startedAt { demo?.shower = .showering(start) }
                if record.showerOver { demo?.shower = .stopped }
                shower.showDemoPage(record)
                ShowerPageDemo.apply(url.lastPathComponent, to:shower)
                // The card's records show one shower charged: the stopped one, or the newest kept.
                if url.lastPathComponent == "sh-detail-stopped-charged" {
                    demo = demo.map { ShowerPageDemo.charging($0, started:record.startedAt) }
                }
                if let kept = shower.demoRetained {
                    demo = demo.map { ShowerPageDemo.charging($0, started:ShowerPageDemo.chargedStart(kept)) }
                }
                if url.lastPathComponent == "sh-endfail" { shower.page.endFailed = .noConnection }
                if url.lastPathComponent == "sh-stopped-busy-rechecking" { shower.page.rechecking = true }
                if let block = ShowerPageDemo.block(url.lastPathComponent), url.lastPathComponent.hasPrefix("sh-home-block-") {
                    // Home itself: the reason under 开始洗澡, nothing pushed.
                    shower.page.presented = false
                    demo?.showerBlockCaption = block.warm
                    return
                }
                if url.lastPathComponent.hasPrefix("sh-detail") {
                    // The 热水洗澡 screen over home, the page down.
                    shower.page.presented = false
                    path = [.shower]
                }
                return
            }
            let settingsDemos: [String:UNAuthorizationStatus] = ["settings":.authorized, "settings-notif-off":.denied,
                                                                  "settings-ask":.notDetermined, "settings-password-on":.authorized,
                                                                  "settings-paused":.authorized, "settings-paused-noanswer":.authorized,
                                                                  "settings-web-login":.authorized,
                                                                  "settings-reset-shower":.authorized, "settings-reset-kept":.authorized,
                                                                  "settings-laundry-off":.authorized, "settings-laundry-locked":.authorized,
                                                                  "settings-theme":.authorized, "settings-theme-shower":.authorized,
                                                                  "settings-theme-laundry":.authorized, "settings-theme-both":.authorized]
            reminders.demoStatus = settingsDemos[url.lastPathComponent]
            guard let result = HomeDemo.handle(url) else { return }
            onboarding = nil; settings = false; path = []; laundryDemo = nil; recordsDemo = nil; washerDemo = nil
            withAnimation(Theme.spring) {
                demo = result?.0
                panel = result?.1
            }
            if settingsDemos[url.lastPathComponent] != nil {
                // Let any open sheet dismiss first, otherwise the reopen is coalesced away.
                Task { try? await Task.sleep(for:.milliseconds(500)); settings = true }
            }
    }
    /// campusdaily://demo/sh-<face>: connect, run, endfail (back on the timer after an end that
    /// didn't go through), settle, done, nocon, denied, busy, stopped (over, kept for the school),
    /// unsure (a settlement without an answer: the same stopped page), stopped-busy (the next
    /// start found the controller in use), stopped-busy-rechecking (再查一次 running), and
    /// detail-stopped (the 热水洗澡 screen over the stopped record).
    /// Also sh-denied-final (the refused face without its retry), sh-detail-kept /
    /// sh-detail-kept-list (热水洗澡 ready, with three synthetic kept showers, the newest charged
    /// on the card's records; -list opens 暖橙's list over it), and sh-detail-stopped-charged
    /// (detail-stopped with its charge on the card's records).
    /// sh-detail-ready / -run / -done (`detail`): 暖橙's 热水洗澡 before a start, running, settled.
    /// sh-detail-block-<reason> (`blocks`): 热水洗澡 set up and idle, 开始洗澡 greyed out with
    /// that reason (-balance: the card at -¥0.50); sh-home-block-account / -signout: 暖橙's home with the reason under 开始洗澡.
    enum ShowerPageDemo {
        /// The greyed-out 开始洗澡 demos, by the name after sh-detail-block- / sh-home-block-.
        static let blocks: [String:ShowerStartBlock] = [
            "unconfigured":.notConfigured, "platform":.platformMissing, "account":.accountChanged,
            "signout":.signOutUnfinished, "inspecting":.inspecting, "busy":.busy, "storage":.storage,
            "unreadable":.recordUnreadable, "unsettled":.unsettled, "launching":.launching,
            "balance":.balanceNegative,
        ]
        /// What the card owes on sh-detail-block-balance (synthetic).
        static let owed = Money(fen:-50)
        static func block(_ name: String?) -> ShowerStartBlock? {
            guard let name else { return nil }
            for prefix in ["sh-detail-block-", "sh-home-block-"] where name.hasPrefix(prefix) {
                return blocks[String(name.dropFirst(prefix.count))]
            }
            return nil
        }

        static func record(_ name: String, now: Date = Date()) -> ShowerState? {
            switch name {
            case "sh-denied-final": return SampleData.showerRecord("sh-denied", now:now)
            case "sh-detail-stopped-charged": return SampleData.showerRecord("sh-detail-stopped", now:now)
            case "sh-detail-kept", "sh-detail-kept-list": return .idle
            case "sh-detail-ready", "sh-detail-run", "sh-detail-done": return detail(name, now:now)
            case _ where name.hasPrefix("sh-detail-first-"): return .idle
            case "sh-first-passed":
                var s = ShowerState(phase:.authorizing, machineID:dormMachine, peripheralID:"demo")
                s.authorizeSent = true
                return s
            case _ where name.hasPrefix("sh-detail-block-") || name.hasPrefix("sh-home-block-"): return block(name) == nil ? nil : .idle
            default: return SampleData.showerRecord(name, now:now)
            }
        }

        /// 暖橙's 热水洗澡 drawn set up in the demo dorm on a synthetic record: before a start, water
        /// running (结束并结算) and settled (the cost).
        static func detail(_ name: String?, now: Date = Date()) -> ShowerState? {
            switch name {
            case "sh-detail-ready": return .idle
            case "sh-detail-run": return SampleData.showerRecord("sh-run", now:now)
            case "sh-detail-done": return SampleData.showerRecord("sh-done", now:now)
            default: return nil
            }
        }

        /// The demo dorm's controller (fake).
        static let dormMachine = "11223344"

        /// Three kept showers (fake controllers): two reasons, one that never started; two on the
        /// dorm's own controller, one on another.
        static func retained(now: Date = Date()) -> ShowerRetainedSummary {
            ShowerRetainedSummary(entries:[
                .init(started:now.addingTimeInterval(-26 * 3600), machine:dormMachine, reason:.stopped),
                .init(started:nil, machine:dormMachine, reason:.authorizeUnclear),
                .init(started:now.addingTimeInterval(-3 * 3600), machine:"AABBCCDD", reason:.closeUnconfirmed),
            ], currentMachine:dormMachine)
        }

        static func isKept(_ name: String?) -> Bool { name?.hasPrefix("sh-detail-kept") == true }

        /// The kept shower the demos show charged: the newest that started.
        static func chargedStart(_ kept: ShowerRetainedSummary) -> Date? { kept.entries.compactMap(\.started).max() }

        /// `data` with a synthetic ¥1.32 hot-water payment on the card stamped with `started` (the
        /// school's calendar, as the school writes it): 「校园卡已扣 ¥1.32」 for the shower started then.
        static func charging(_ data: HomeData, started: Date?) -> HomeData {
            var data = data
            guard let started, var activity = data.snapshot.activity.value else { return data }
            let school = data.calendar
            let c = school.dateComponents([.year, .month, .day, .hour, .minute, .second], from:started)
            activity.records.append(CardRecord(date:String(format:"%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
                                               time:String(format:"%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0),
                                               title:"蓝牙热水", amount:Money(fen:132), balanceAfter:nil, direction:"1"))
            activity.records.sort { ($0.moment(calendar:school) ?? .distantPast) > ($1.moment(calendar:school) ?? .distantPast) }
            data.snapshot.activity.succeed(activity, at:data.snapshot.activity.fetchedAt ?? Date())
            return data
        }

        /// 订单 under a page demo: the synthetic list for the kept showers (their line opens it),
        /// nil to leave it as it is.
        static func records(_ name: String) -> RecordsDemo? { isKept(name) ? .list : nil }

        /// The demo knobs on the model, for this page demo (and cleared for any other).
        @MainActor static func apply(_ name: String?, to shower: ShowerModel) {
            shower.demoDeniedFinal = name == "sh-denied-final"
            let kept = isKept(name)
            shower.demoRetained = kept ? retained() : nil
            shower.demoRetainedListOpen = name == "sh-detail-kept-list"
            // 暖橙's 热水洗澡 reads the live model: drawn set up and idle instead.
            let block = block(name)
            shower.demoStartBlock = block
            let first = name?.hasPrefix("sh-detail-first-") == true
            let detailRecord = detail(name)
            shower.demoDetailRecord = detailRecord
            shower.demoReadyDorm = kept || first || detailRecord != nil || (block != nil && block != .notConfigured) ? SampleData.dorm : nil
            shower.demoFirstCheck(name)
        }
    }

    /// campusdaily://demo/notify/<kind>
    /// A page pushed anew, so its @State starts from the demo: after the settings sheet has gone
    /// when it is up (`open(_:)`), otherwise a moment after home's pages are popped.
    func freshPush(_ route: HomeRoute) {
        if settings { open([route], from:.deepLink); return }
        path = []; pathAfterSettings = nil
        Task { try? await Task.sleep(for:.milliseconds(350)); path = [route] }
    }

    func notifyDemo(_ url: URL) -> String? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "notify" else { return nil }
        return parts.count > 1 ? parts[1] : "laundry"
    }

    func demoTap(_ kind: HomeShowerButton.Kind) {
        switch kind {
        case .start:
            startTick += 1
            withAnimation(Theme.spring) { demo?.shower = .showering(Date()) }
        case .showering where shower.page.record.phase == .running:
            // Collapsed from a demo page: open it again, as the live button does.
            shower.pageEvent(.reopen)
        case .showering(let start, _):
            withAnimation(Theme.spring) { demo?.shower = .settling(start) }
            Task {
                try? await Task.sleep(for:.seconds(1.5))
                let minutes = max(1, Int((Date().timeIntervalSince(start) / 60).rounded()))
                withAnimation(Theme.spring) {
                    demo?.shower = .idle
                    demo?.lastShowerMinutes = minutes; demo?.lastShowerCost = Decimal(string:"1.32"); demo?.lastShowerEnded = Date()
                    demo?.appActivities.insert(AppActivity(id:"demo-\(Date().timeIntervalSince1970)", kind:.shower(minutes:minutes),
                                                           date:Date(), amount:Money(fen:132)), at:0)
                }
                successTick += 1
                if let record = ShowerPageDemo.record("sh-done") { shower.showDemoPage(record) }
            }
        case .signIn: openOnboarding(from:.deepLink)
        case .settling: path.append(.shower)
        case .stopped: shower.pageEvent(.reopen)
        case .starting: break
        }
    }
}
#endif
