import Foundation
import SwiftUI
import UserNotifications
import WidgetKit
import Core

/// Settings › 提醒 values (app UserDefaults). The two lines are mirrored to the widget via `ReminderLines`.
enum ReminderKey {
    static let powerLow = PreferenceKey.reminder("powerLow")
    static let cardLow = PreferenceKey.reminder("cardLow")
    static let unsettledMinutes = PreferenceKey.reminder("unsettledMinutes")
    static let laundryDone = PreferenceKey.reminder("laundryDone")
    static let powerLine = PreferenceKey.reminder("powerLine")
    static let cardLine = PreferenceKey.reminder("cardLine")
    /// The pre-permission sheet has been shown (by any automatic trigger: first toggle on, first paid
    /// laundry order, first home read). Once set, it only shows again from Settings' 「打开提醒」 row.
    static let prompted = PreferenceKey.reminder("prompted")
    // De-dupe for low power / card: armed again once the value is back above the line.
    static let powerArmed = PreferenceKey.reminder("powerArmed")
    static let cardArmed = PreferenceKey.reminder("cardArmed")
    static let powerSentDay = PreferenceKey.reminder("powerSentDay")
    static let cardSentDay = PreferenceKey.reminder("cardSentDay")
    // The laundry-done request currently scheduled.
    static let laundryOrder = PreferenceKey.reminder("laundryOrder")
    static let laundryEnd = PreferenceKey.reminder("laundryEnd")

    static func registerDefaults(in defaults: UserDefaults) {
        defaults.register(defaults:[powerLow:true, cardLow:true, unsettledMinutes:30, laundryDone:true,
                                                 powerLine:10, cardLine:20, powerArmed:true, cardArmed:true])
    }
    static func lines(in defaults: UserDefaults) -> ReminderLines {
        ReminderLines(powerKWh:defaults.integer(forKey:powerLine), cardYuan:defaults.integer(forKey:cardLine))
    }
}

/// Local notifications and the pre-permission sheet. Never touches orders or payments:
/// it only reads facts the models already have. The live app's (`shared`) has the notification
/// center and the app's preferences; a sample's (`sample(defaults:)`) has neither: it schedules,
/// asks and shows nothing, and keeps its settings in the sample's preferences.
@MainActor final class Reminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders(defaults:.standard, center:.current())
    static func sample(defaults: UserDefaults) -> Reminders { Reminders(defaults:defaults, center:nil) }

    enum PromptOrigin: String, Identifiable { case settings, app; var id: String { rawValue } }
    typealias Route = NotificationRoute

    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Pre-permission sheet to show, and where (settings sheet or the home root).
    @Published var prompt: PromptOrigin?
    /// Notification tapped: HomeView navigates and clears it.
    @Published var route: Route?
    /// An app trigger (first paid laundry order, first home read) is waiting for home to be visible
    /// (`queue`; held while the sample covers the live app).
    @Published private(set) var appPromptPending = false
    #if DEBUG
    /// Forces the settings 提醒 group into on / notifications-off / not-asked for screenshots.
    @Published var demoStatus: UNAuthorizationStatus?
    /// campusdaily://demo/permission-home: the next pending app prompt ignores the flag and the real status.
    private var demoForcePrompt = false
    #endif

    /// The notification center; nil for a sample's, which reaches no notification at all.
    private let center: UNUserNotificationCenter?
    let defaults: UserDefaults
    private let queue: ReminderPromptQueue
    private var laundryPlan: LaundryPlan?
    private var showerStart: Date?
    /// The campus numbers the low-balance reminders judge again (`reevaluateCampus`).
    var campusSnapshot: () -> HomeSnapshot = { .empty }
    /// True while the live app is covered by the sample: a queued prompt waits (`ReminderPromptQueue`).
    var held: () -> Bool {
        get { queue.held }
        set { queue.held = newValue }
    }

    private init(defaults: UserDefaults, center: UNUserNotificationCenter?) {
        self.defaults = defaults
        self.center = center
        queue = ReminderPromptQueue(storage:defaults, promptedKey:ReminderKey.prompted)
        super.init()
        ReminderKey.registerDefaults(in:defaults)
        guard let center else { return }
        center.delegate = self
        shareLines()
        Task { await refreshAuthorization() }
    }

    /// After a reset: nothing scheduled or shown is about this install's old data any more.
    func clearAfterReset() {
        center?.removeAllPendingNotificationRequests()
        center?.removeAllDeliveredNotifications()
        laundryPlan = nil; showerStart = nil
        queue.clear(); appPromptPending = false; prompt = nil; route = nil
    }

    var effectiveStatus: UNAuthorizationStatus {
        #if DEBUG
        if let demoStatus { return demoStatus }
        #endif
        return authorization
    }
    var denied: Bool { effectiveStatus == .denied }
    /// The 「洗衣洗好时」 reminder is on and notifications are allowed, so a running wash will notify.
    var laundryDoneWillNotify: Bool {
        let allowed = [.authorized, .provisional, .ephemeral].contains(effectiveStatus)
        return center != nil && allowed && defaults.bool(forKey:ReminderKey.laundryDone)
    }
    /// The system hasn't asked yet: settings shows the 「打开提醒」 row.
    var notAsked: Bool { effectiveStatus == .notDetermined }

    func refreshAuthorization() async {
        guard let center else { return }
        let old = authorization
        authorization = await center.notificationSettings().authorizationStatus
        // Just allowed (here or in system Settings): requests added while not allowed were dropped, add them again.
        if old != authorization, authorization == .authorized {
            cancelLaundry()
            resync()
            reevaluateCampus()
        }
    }

    // MARK: Permission

    /// Three automatic triggers share one persisted flag: whichever comes first shows the sheet, once ever
    /// (「以后再说」 included). Only while the system hasn't been asked.
    /// A sample's never asks.
    private var mayAutoPrompt: Bool {
        center != nil && authorization == .notDetermined && !queue.prompted
    }
    /// Trigger 1: a reminder toggle switched on in settings (shown inside the settings sheet).
    func maybePrompt(from origin: PromptOrigin) {
        guard mayAutoPrompt, prompt == nil else { return }
        queue.markShown()
        prompt = origin
    }
    /// Triggers 2 and 3 (first paid laundry order, first home read): queued until home is visible
    /// with nothing on top (HomeView calls `presentPendingPrompt`).
    func requestAppPrompt() {
        queue.request(notDetermined:center != nil && authorization == .notDetermined)
        appPromptPending = queue.pending
    }
    /// Trigger 3: home read both the power and the card balance successfully, so the user has seen the numbers.
    func campusRead(_ snapshot: HomeSnapshot) {
        guard snapshot.card.error == nil, snapshot.card.value != nil,
              snapshot.power.error == nil, snapshot.power.value?.remainingKWh != nil else { return }
        requestAppPrompt()
    }
    /// Home is visible and clear: show the queued sheet (re-checks the real status first).
    /// Held (the sample came up while this waited): still queued, nothing stored or shown.
    func presentPendingPrompt() async {
        guard queue.pending, !held() else { return }
        await refreshAuthorization()
        var force = false
        #if DEBUG
        if demoForcePrompt { force = true; demoForcePrompt = false }
        #endif
        let show = queue.take(notDetermined:center != nil && authorization == .notDetermined, showing:prompt != nil, force:force)
        appPromptPending = queue.pending
        guard show else { return }
        prompt = .app
    }
    /// Settings 「打开提醒」 row: the user asked, so it shows whatever the flag says.
    func showPrompt(from origin: PromptOrigin) {
        guard center != nil, prompt == nil else { return }
        queue.markShown()
        prompt = origin
    }
    /// 「打开提醒」: the only place that asks the system; never while held.
    func requestAuthorization() async {
        prompt = nil
        guard let center, !held() else { return }
        _ = try? await center.requestAuthorization(options:[.alert, .sound, .badge])
        await refreshAuthorization()
    }

    /// Sheet binding for one origin: shows only that origin's prompt; dismissing clears it.
    func promptBinding(_ origin: PromptOrigin) -> Binding<PromptOrigin?> {
        Binding<PromptOrigin?>(get: { [weak self] in self?.prompt == origin ? origin : nil },
                               set: { [weak self] value in if value == nil { self?.prompt = nil } })
    }

    // MARK: Settings changes

    /// Mirror the lines to the widget and redraw it.
    func shareLines() {
        guard center != nil else { return }
        let lines = ReminderKey.lines(in:defaults)
        if ReminderLines.shared() != lines { lines.share(); WidgetCenter.shared.reloadAllTimelines() }
    }
    /// A line or a low-balance switch changed: judge the last reading again (re-arms when it is back above).
    func reevaluateCampus() {
        evaluateCampus(campusSnapshot())
    }
    /// Re-apply scheduled reminders after a setting or the authorization changed.
    func resync() {
        if let laundryPlan { applyLaundry(laundryPlan) } else { cancelLaundry() }
        syncShower(started:showerStart)
    }

    // MARK: Laundry done

    private struct LaundryPlan: Equatable { var orderId: String; var end: Date; var machine: String }

    /// Called whenever the order or machine reading changes (LaundryModel.syncActivity).
    func syncLaundry(facts: LaundryFacts, now: Date = Date()) {
        switch facts.phase(now:now) {
        // Paid: the moment to explain reminders.
        case .running, .starting: requestAppPrompt()
        default: break
        }
        switch LaundryDoneReminder.step(facts.configured ? facts.record : nil, scheduled:scheduledLaundry, now:now) {
        case .schedule(let reminder):
            let plan = LaundryPlan(orderId:reminder.orderID, end:reminder.end, machine:facts.machine.map(LaundryFormat.machine) ?? "洗衣机")
            laundryPlan = plan
            applyLaundry(plan)
        case .keep:
            break
        case .cancel:
            laundryPlan = nil
            cancelLaundry()
        }
    }
    /// The laundry-done request set now.
    private var scheduledLaundry: LaundryDoneReminder.Plan? {
        guard let id = defaults.string(forKey:ReminderKey.laundryOrder),
              let end = defaults.object(forKey:ReminderKey.laundryEnd) as? Date else { return nil }
        return LaundryDoneReminder.Plan(orderID:id, end:end)
    }
    private func applyLaundry(_ plan: LaundryPlan) {
        guard let center else { return }
        guard defaults.bool(forKey:ReminderKey.laundryDone) else { cancelLaundry(); return }
        // Reschedule only when the order changed or the end moved (the order re-read refines it).
        if LaundryDoneReminder.isScheduled(LaundryDoneReminder.Plan(orderID:plan.orderId, end:plan.end), as:scheduledLaundry) { return }
        cancelLaundry()
        let delay = plan.end.timeIntervalSinceNow
        guard delay > 1 else { return }
        let content = make(title:"衣服洗好了", body:"\(plan.machine)洗完了，去拿衣服吧。", thread:"laundry", route:.laundry, sound:true)
        let id = "laundry-" + plan.orderId
        center.add(UNNotificationRequest(identifier:id, content:content,
                                         trigger:UNTimeIntervalNotificationTrigger(timeInterval:delay, repeats:false)))
        defaults.set(plan.orderId, forKey:ReminderKey.laundryOrder); defaults.set(plan.end, forKey:ReminderKey.laundryEnd)
    }
    private func cancelLaundry() {
        guard let center, let id = defaults.string(forKey:ReminderKey.laundryOrder) else { return }
        center.removePendingNotificationRequests(withIdentifiers:["laundry-" + id])
        defaults.removeObject(forKey:ReminderKey.laundryOrder); defaults.removeObject(forKey:ReminderKey.laundryEnd)
    }

    // MARK: Shower still running

    /// Called on every session change (ShowerModel). `started` = start of a session that can still be closed.
    func syncShower(started: Date?) {
        showerStart = started
        guard let center else { return }
        let minutes = defaults.integer(forKey:ReminderKey.unsettledMinutes)
        let wanted = started.flatMap { start -> String? in
            minutes > 0 ? "shower-\(Int(start.timeIntervalSince1970))-\(minutes)" : nil
        }
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("shower-") }
            let stale = pending.filter { $0 != wanted }
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers:stale) }
            if started == nil {
                // Settled: take an old 「还在计时」 off Notification Center.
                let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("shower-") }
                center.removeDeliveredNotifications(withIdentifiers:delivered)
            }
            guard let start = started, let wanted, !pending.contains(wanted) else { return }
            let delay = start.addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSinceNow
            guard delay > 1 else { return }
            let content = make(title:"还在计时", body:"已经洗了 \(minutes) 分钟，洗完记得结束并结算。", thread:"shower", route:.home, sound:true)
            try? await center.add(UNNotificationRequest(identifier:wanted, content:content,
                                                        trigger:UNTimeIntervalNotificationTrigger(timeInterval:delay, repeats:false)))
        }
    }

    // MARK: Low power / low card

    /// After each campus read (foreground, pull to refresh, background refresh). Only fresh, successful values count.
    func evaluateCampus(_ snapshot: HomeSnapshot, now: Date = Date()) {
        guard center != nil else { return }
        let lines = ReminderKey.lines(in:defaults)
        if snapshot.power.error == nil, let meter = snapshot.power.value, let left = meter.remainingKWh {
            evaluate(kind:"power", low:left < lines.power, enabled:ReminderKey.powerLow,
                     armed:ReminderKey.powerArmed, sentDay:ReminderKey.powerSentDay, now:now) {
                self.make(title:"宿舍快没电了", body:Self.powerBody(meter, now:now), thread:"power", route:.home, sound:false)
            }
        }
        if snapshot.card.error == nil, let balance = snapshot.card.value?.yuan {
            evaluate(kind:"card", low:balance < lines.card, enabled:ReminderKey.cardLow,
                     armed:ReminderKey.cardArmed, sentDay:ReminderKey.cardSentDay, now:now) {
                self.make(title:"校园卡余额不多了", body:"只剩 \(Theme.yuan(balance))，记得充值。", thread:"card", route:.home, sound:false)
            }
        }
    }
    /// Once per crossing: sent when the value drops below the line, not again until it is back above
    /// (and at most once a day). Back above: re-armed and the old banner removed from Notification Center.
    private func evaluate(kind: String, low: Bool, enabled: String, armed: String, sentDay: String, now: Date,
                          content: () -> UNMutableNotificationContent) {
        guard let center else { return }
        guard low else {
            defaults.set(true, forKey:armed)
            center.removeDeliveredNotifications(withIdentifiers:[kind])
            return
        }
        let today = Self.dayKey(now)
        guard defaults.bool(forKey:enabled), defaults.bool(forKey:armed), defaults.string(forKey:sentDay) != today,
              authorization == .authorized || authorization == .provisional || authorization == .ephemeral else { return }
        center.add(UNNotificationRequest(identifier:kind, content:content(), trigger:nil))
        defaults.set(false, forKey:armed); defaults.set(today, forKey:sentDay)
    }
    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from:date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
    /// 「只剩 8.6 度，大约能用到明晚。记得充电费。」 when yesterday's use gives 今晚/明晚, else the short form.
    static func powerBody(_ meter: Meter, now: Date = Date(), calendar: Calendar = .current) -> String {
        let remaining = meter.remainingKWh ?? 0
        let left = Theme.kwh(remaining)
        if let used = meter.dailyUseKWh, used > 0 {
            let hours = NSDecimalNumber(decimal:remaining / used).doubleValue * 24
            let end = now.addingTimeInterval(hours * 3600)
            let word: String? = calendar.isDate(end, inSameDayAs:now) ? "今晚"
                : calendar.date(byAdding:.day, value:1, to:now).map { calendar.isDate(end, inSameDayAs:$0) } == true ? "明晚" : nil
            if let word { return "只剩 \(left) 度，大约能用到\(word)。记得充电费。" }
        }
        return "只剩 \(left) 度了，记得充电费。"
    }

    // MARK: Content and delivery

    private func make(title: String, body: String, thread: String, route: Route, sound: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        content.threadIdentifier = thread
        content.interruptionLevel = .active   // no time-sensitive entitlement
        if sound { content.sound = .default }
        content.userInfo = route.userInfo
        return content
    }

    // UIKit's completion handlers must run on the main thread: on a launch from a tapped banner, one
    // called elsewhere ends the app. The `async` forms of these methods finish on a background
    // thread, so these take the handlers and call them on main.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in done([.banner, .list, .sound]) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = Route(userInfo:response.notification.request.content.userInfo)
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            self.route = route
            done()
        }
    }

    #if DEBUG
    /// campusdaily://demo/permission-home: behave as if the first home read just succeeded.
    func demoHomeRead() {
        demoForcePrompt = true
        queue.request(notDetermined:true)
        appPromptPending = queue.pending
    }
    /// campusdaily://demo/notify/<laundry|shower|power|power-short|card> — the real copy, delivered in 5 s (time to go to the home screen).
    func demoNotify(_ kind: String) async {
        guard let center else { return }
        if authorization == .notDetermined { await requestAuthorization() }
        let content: UNMutableNotificationContent
        switch kind {
        case "laundry": content = make(title:"衣服洗好了", body:"3 号机洗完了，去拿衣服吧。", thread:"laundry", route:.laundry, sound:true)
        case "shower": content = make(title:"还在计时", body:"已经洗了 30 分钟，洗完记得结束并结算。", thread:"shower", route:.home, sound:true)
        case "power-short": content = make(title:"宿舍快没电了", body:"只剩 8.6 度了，记得充电费。", thread:"power", route:.home, sound:false)
        case "card": content = make(title:"校园卡余额不多了", body:"只剩 ¥18.40，记得充值。", thread:"card", route:.home, sound:false)
        default: content = make(title:"宿舍快没电了", body:"只剩 8.6 度，大约能用到明晚。记得充电费。", thread:"power", route:.home, sound:false)
        }
        try? await center.add(UNNotificationRequest(identifier:"demo-" + kind + "-\(Int(Date().timeIntervalSince1970))", content:content,
                                                    trigger:UNTimeIntervalNotificationTrigger(timeInterval:5, repeats:false)))
    }
    #endif
}

/// Pre-permission sheet: group bg, ~300pt detent, padding 24, no mascot.
struct ReminderPermissionSheet: View {
    @EnvironmentObject private var reminders: Reminders
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            Text("电快没了、衣服洗好了，\n校日常会\(Text("提醒你").foregroundStyle(Theme.accentLarge))。")
                .scaledFont(24, .bold, relativeTo:.title2).foregroundStyle(Theme.ink)
                .fixedSize(horizontal:false, vertical:true)
            Text("只在这几种时候提醒：电量或校园卡低于你设的数、衣服洗好、洗完澡忘了结算。")
                .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal:false, vertical:true)
                .padding(.top,10)
            Button { Task { await reminders.requestAuthorization() } } label: { DockPillLabel(title:"打开提醒") }
                .buttonStyle(PressScaleStyle())
                .padding(.top,24)
            Button { reminders.prompt = nil } label: {
                Text("以后再说").scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                    .frame(maxWidth:.infinity).frame(minHeight:44)
            }
            .padding(.top,4)
        }
        .padding(.horizontal,24).padding(.top,28).padding(.bottom,8)
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
        // ≈300pt at the default size; large text gets the full-height detent.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(300), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.group)
        .typesettingLanguage(Theme.typesetting)
    }
}

/// Home-root hooks: the pre-permission sheet after the first paid laundry order or the first home read
/// (the settings triggers show it inside settings), and notification taps (laundry → laundry page, the rest → home).
struct ReminderHooks: ViewModifier {
    /// The root's notification tap: unless a payment may be under way, back to home, with the
    /// laundry page shown for `.laundry`.
    let open: (Reminders.Route) -> Void
    /// Home is visible with nothing on top (no onboarding, sheet, cover, panel or pushed page).
    var homeClear: Bool
    @EnvironmentObject private var reminders: Reminders
    func body(content: Content) -> some View {
        content
            .sheet(item:reminders.promptBinding(.app)) { _ in
                ReminderPermissionSheet()
            }
            .task(id:reminders.appPromptPending && homeClear) {
                guard reminders.appPromptPending, homeClear else { return }
                // Let a sheet or cover that just closed finish, so the presentation isn't dropped.
                try? await Task.sleep(for:.milliseconds(600))
                guard !Task.isCancelled else { return }
                await reminders.presentPendingPrompt()
            }
            // initial: a tap that launched the app may set the route before this view is attached.
            .onChange(of:reminders.route, initial:true) { _, route in
                guard let route else { return }
                reminders.route = nil
                open(route)
            }
    }
}
