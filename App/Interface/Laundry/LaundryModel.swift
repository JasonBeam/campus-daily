import Foundation
import Combine
import UIKit
import Core

/// UI state over `UjingClient` (login, machine reads) and `LaundryEngine` (order + payment).
/// No ordering or payment rules here: the engine decides what may be sent.
/// Another U净 account tried to sign in while an order placed with the stored one is open.
enum LaundryLoginRefusal: Error { case otherAccount }

/// Runs on the `CampusServices` it is given: the live app's, or a sample's (whose U净 client
/// sends nothing and whose payments open nothing).
@MainActor final class LaundryModel: ObservableObject {
    let services: CampusServices
    private let reminders: Reminders
    /// The lock screen's laundry activity; nil for a sample's.
    private let activities: LaundryActivityController?
    private var defaults: UserDefaults { services.defaults }
    private var vault: StoredLaundryVault { services.laundryVault }
    @Published private(set) var configured = false
    @Published private(set) var accountConnected = false
    @Published private(set) var loading = false
    @Published private(set) var snapshot: WasherSnapshot?
    @Published private(set) var issue: String?
    @Published private(set) var checkout: LaundryCheckout?
    @Published private(set) var checkoutBusy = false
    @Published private(set) var checkoutIssue: String?
    @Published private(set) var checkoutProgress: String?
    @Published private(set) var savedMachines: [SavedWasher] = []
    @Published private(set) var candidate: WasherSnapshot?
    @Published private(set) var storageBlocked = false
    @Published private(set) var selectedMachineID: String?
    /// Machines saved (the same one again included) or switched to since launch: the first-run
    /// step finishes on each (`WasherSetupExit.finishesSetupStep`).
    @Published private(set) var machineChoices = 0
    /// The number the U净 login was made with (nil signed out, or saved by an earlier build).
    @Published private(set) var ujingMobile: String?
    /// U净 said the login ran out (a machine read or an order step): 「重新登录 U净」 is offered.
    @Published private(set) var sessionExpired = false
    /// The last 退出 U净 didn't go through: said under the button until one does.
    @Published private(set) var signOutFailed = false
    /// 「学校洗衣机」 (Settings / first-run question). Off: laundry hidden everywhere, no reads,
    /// no Live Activity, no reminder; the U净 login and saved machines stay.
    @Published private(set) var schoolEnabled: Bool
    @Published private(set) var lastOrder: LaundryLastOrder?

    private var account: UjingAccountItem?
    private var engine: LaundryEngine?
    private var observer: Task<Void, Never>?
    private var lastAttempt: Date?
    private var activitySync: AnyCancellable?
    private var endCheck: (end: Date, task: Task<Void, Never>)?
    private var startWatch: (since: Date, task: Task<Void, Never>)?
    private static let machinesKey = PreferenceKey.laundryMachines
    private static let selectedKey = PreferenceKey.laundrySelected
    nonisolated static let lastOrderKey = PreferenceKey.laundryLastOrder

    init(services: CampusServices, reminders: Reminders, activities: LaundryActivityController?) {
        self.services = services
        self.reminders = reminders
        self.activities = activities
        schoolEnabled = SchoolLaundryPreference(storage:services.defaults).isOn
        lastOrder = services.defaults.data(forKey:LaundryModel.lastOrderKey).flatMap { try? JSONDecoder().decode(LaundryLastOrder.self, from:$0) }
        reloadAccount()
        // Live Activity + reminder follow every change of the order or machine reading.
        activitySync = $checkout.combineLatest($snapshot, $configured, $schoolEnabled)
            .debounce(for:.milliseconds(50), scheduler:RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.syncActivity() } }
    }

    // MARK: 学校洗衣机

    /// Same rule for the switch everywhere: off only once no order is unfinished.
    var schoolSwitchLocked: Bool {
        SchoolLaundryPreference.switchLocked(isOn:schoolEnabled, checkout:checkout?.phase, busy:checkoutBusy)
    }

    /// No confirmation; turning on restores the saved login and machines at once.
    func setSchoolEnabled(_ on: Bool) {
        guard on != schoolEnabled else { return }
        if !on, !SchoolLaundryPreference.mayTurnOff(checkout:checkout?.phase, busy:checkoutBusy) { return }
        SchoolLaundryPreference(storage:defaults).set(on)
        schoolEnabled = on
        if on { Task { await refresh(force:true) } } else { snapshot = nil; issue = nil; lastAttempt = nil }
        syncActivity()
    }

    // MARK: Account + engine

    /// The install's `x-mobile-id`: a dashed UUID (the client rejects anything else), created once
    /// and saved so the SMS request and the login send the same id.
    private var device: UjingDevice {
        if account == nil, let id = try? vault.mobileID() { account = UjingAccountItem(mobileID:id) }
        return UjingDevice(mobileID:account?.mobileID ?? UUID().uuidString, userAgent:AppEnvironment.userAgent)
    }

    private func reloadAccount() {
        do {
            account = try vault.accountItem()
            issue = nil
        } catch {
            issue = "解锁手机后再打开校日常。"
        }
        accountConnected = account?.account != nil
        ujingMobile = account?.account != nil ? account?.mobile : nil
        savedMachines = Self.loadMachines(from:defaults)
        selectedMachineID = defaults.string(forKey:Self.selectedKey).flatMap { id in
            savedMachines.contains { $0.id == id } ? id : nil
        } ?? savedMachines.first?.id
        configured = accountConnected && selectedMachine != nil
        rebuildEngine()
    }

    private var selectedMachine: SavedWasher? { savedMachines.first { $0.id == selectedMachineID } }

    private var client: UjingClient {
        if let signedIn = account?.account { return UjingClient(http:services.laundryHTTP, device:device, account:signedIn) }
        return UjingClient(http:services.laundryHTTP, device:device)
    }

    /// Alipay for the live app; a sample's opens nothing (`SamplePaymentLauncher`).
    private var launcher: any PaymentLauncher {
        guard services.kind == .live else { return SamplePaymentLauncher() }
        return AlipayPaymentLauncher(returned:{ [weak self] in Task { await self?.refreshOrder() } })
    }

    private func rebuildEngine() {
        guard !checkoutBusy else { return }
        observer?.cancel(); observer = nil; engine = nil
        do {
            let engine = try LaundryEngine(api:client, vault:vault, launcher:launcher,
                                           accountID:account?.account?.id,
                                           resetMarker:services.resetMarker,
                                           inFront:services.laundryInFront(live:Self.appInFront),
                                           debugLog:services.debugLog)
            self.engine = engine
            observer = Task { [weak self] in
                let blocked = await engine.storageBlocked
                self?.storageBlocked = blocked
                for await next in await engine.updates() {
                    guard let self else { return }
                    self.apply(next)
                    self.storageBlocked = await engine.storageBlocked
                }
            }
        } catch {
            storageBlocked = true
            checkout = (try? vault.checkout()) ?? nil
        }
    }

    private func apply(_ next: LaundryCheckout) {
        if let id = next.orderID, let draft = next.draft {
            let note = LaundryLastOrder(orderID:id, program:draft.program, machineName:draft.machineName, amount:next.order?.price)
            if note != lastOrder {
                lastOrder = note
                defaults.set(try? JSONEncoder().encode(note), forKey:Self.lastOrderKey)
            }
        }
        if checkout != next { checkout = next }
    }

    // MARK: Login (UjingLoginView)

    /// `GET captcha`. Never retried automatically.
    func requestSMS(mobile: String) async throws {
        try await client.requestSMS(mobile:mobile)
    }

    /// With an order open (its login expired), only the account that placed it may sign in again:
    /// the new login is checked before anything is saved (`LaundryCheckout.allowsLogin`).
    /// The order record can't be read (`storageBlocked`): the account that placed an open order
    /// is unknown, so no login is accepted (fail closed).
    func login(mobile: String, code: String) async throws {
        guard mayLogin else { throw LaundryEngineError.busy }
        guard !storageBlocked else { throw LaundryEngineError.storage }
        let device = device
        let signedIn: UjingAccount
        do {
            signedIn = try await UjingClient(http:services.laundryHTTP, device:device).login(mobile:mobile, code:code)
            services.debugLog.record(.ujingLogin(.ok))
        } catch {
            // Its kind and code only: never the number or the code typed.
            services.debugLog.record(.ujingLogin(DebugOutcome(error)))
            throw error
        }
        guard !loading, !checkoutBusy else { throw LaundryEngineError.busy }
        guard !storageBlocked else { throw LaundryEngineError.storage }
        if let record = checkout, !record.allowsLogin(as:signedIn.id, stored:account?.account?.id) {
            throw LaundryLoginRefusal.otherAccount
        }
        let reread = checkout.map { $0.phase != .none } ?? false
        let clearsLastOrder = LaundryCheckout.clearsLastOrder(record:checkout, signedInAs:signedIn.id, stored:account?.account?.id)
        let item = UjingAccountItem(mobileID:device.mobileID, account:signedIn, mobile:mobile)
        try vault.saveAccountItem(item)
        if clearsLastOrder { forgetLastOrder() }
        account = item
        accountConnected = true; ujingMobile = mobile; sessionExpired = false; signOutFailed = false
        configured = selectedMachine != nil
        issue = nil; lastAttempt = nil
        rebuildEngine()
        // The open order is readable again (read only).
        if reread { Task { await refreshOrder() } }
    }

    /// The U净 login entry. With an order open, `login` accepts only the account that placed it.
    var mayLogin: Bool { !loading && !checkoutBusy }

    static func loginText(_ error: Error) -> String {
        if error is LaundryLoginRefusal { return "还有一笔洗衣订单没结束，要用下单的那个 U净 账号登录。" }
        if let error = error as? LaundryEngineError { return error.loginMessage }
        return (error as? ServiceError)?.userMessage ?? "登录没完成，核对手机号和验证码再试。"
    }

    /// Why 退出 U净 can't go now (an unfinished order, a step running), or nil.
    var signOutRefusal: UjingSignOut.Refusal? {
        UjingSignOut.refusal(orderOpen:(checkout?.phase ?? LaundryPhase.none) != LaundryPhase.none, busy:loading || checkoutBusy)
    }

    /// 退出 U净 (`UjingSignOut`): the login goes, the saved machines stay. A login that can't be
    /// written stays signed in rather than coming back at the next launch, and says so.
    func signOut() {
        guard signOutRefusal == nil else { return }
        guard !storageBlocked,
              let outcome = try? UjingSignOut.perform(vault:vault, preferences:defaults, checkout:checkout,
                                                             debugLog:services.debugLog)
        else { signOutFailed = true; return }
        signOutFailed = false
        account = account.map { UjingAccountItem(mobileID:$0.mobileID) }
        accountConnected = false; configured = false; snapshot = nil
        ujingMobile = nil; sessionExpired = false
        issue = nil; checkoutIssue = nil
        if outcome.clearedCheckout { checkout = nil }
        if outcome.forgotLastOrder { lastOrder = nil }
        rebuildEngine()
    }

    /// The finished order's outcome and the last-order note belong to the account that placed
    /// it: they go before the engine is rebuilt from the stored record. Only called with no order
    /// open (`LaundryCheckout.clearsLastOrder`), when the record holds nothing but that outcome.
    private func forgetLastOrder() {
        if checkout?.lastOutcome != nil, (try? vault.saveCheckout(nil)) != nil {
            checkout = nil
        }
        lastOrder = nil
        defaults.removeObject(forKey:Self.lastOrderKey)
    }

    /// After a reset cleared the stores: no U净 login, machines or order; the switch back on.
    func reloadAfterReset() {
        endCheck?.task.cancel(); endCheck = nil
        startWatch?.task.cancel(); startWatch = nil
        schoolEnabled = SchoolLaundryPreference(storage:defaults).isOn
        lastOrder = nil; snapshot = nil; candidate = nil; checkout = nil
        issue = nil; checkoutIssue = nil; checkoutProgress = nil; lastAttempt = nil; sessionExpired = false; signOutFailed = false
        account = nil
        reloadAccount()
        activities?.endAll()
    }

    // MARK: Machines (WasherSetupView)

    private static func loadMachines(from defaults: UserDefaults) -> [SavedWasher] {
        guard let data = defaults.data(forKey:machinesKey) else { return [] }
        return (try? JSONDecoder().decode([SavedWasher].self, from:data)) ?? []
    }
    private func storeMachines(_ list: [SavedWasher]) {
        defaults.set(try? JSONEncoder().encode(list), forKey:Self.machinesKey)
        savedMachines = list
    }

    /// Scanned a code: read the machine (scan + programs), keep it as the candidate.
    func prepareMachine(qrCode: String) async {
        if let refusal = machineChangeRefusal { issue = refusal.message; return }
        guard accountConnected else { issue = "先登录 U净，再添加洗衣机。"; return }
        guard UjingInput.isWasherQR(qrCode) else { issue = "没认出这台洗衣机，换个角度再扫一次。"; return }
        loading = true; issue = nil; candidate = nil
        defer { loading = false }
        do { candidate = try await client.washer(qr:qrCode); sessionExpired = false }
        catch { issue = readText(error) ?? "没认出这台洗衣机，换个角度再扫一次。" }
    }

    /// Throws `WasherSetupRefusal`, whose text the page shows.
    func savePreparedMachine(name: String) throws {
        if let refusal = machineChangeRefusal { throw refusal }
        guard let value = candidate else { throw WasherSetupRefusal.nothingToSave }
        let alias = try WasherSetupRefusal.machineName(name).get()
        storeMachines(SavedWasher.saving(id:value.deviceID, qrCode:value.qrCode, name:alias, in:savedMachines))
        select(value.deviceID)
        snapshot = value
        candidate = nil; issue = nil; checkoutIssue = nil; lastAttempt = Date()
        machineChoices += 1
    }

    /// Throws `WasherSetupRefusal`, whose text the page shows.
    func selectMachine(_ item: SavedWasher) throws {
        if let refusal = machineChangeRefusal { throw refusal }
        guard savedMachines.contains(where:{ $0.id == item.id }) else { throw WasherSetupRefusal.notSaved }
        select(item.id)
        snapshot = nil; issue = nil; checkoutIssue = nil; lastAttempt = nil
        machineChoices += 1
    }

    private func select(_ id: String) {
        selectedMachineID = id
        defaults.set(id, forKey:Self.selectedKey)
        configured = accountConnected
    }

    // MARK: Reads

    /// Machine state (scan + programs). Throttled to once a minute unless forced.
    func refresh(force: Bool = false) async {
        syncActivity()
        guard schoolEnabled, configured, let machine = selectedMachine, !loading else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        loading = true; issue = nil; lastAttempt = Date()
        defer { loading = false }
        do { snapshot = try await client.washer(qr:machine.qrCode); sessionExpired = false }
        catch { issue = readText(error) ?? "暂时连不上 U净，先显示上次的状态。" }
    }

    /// Order read (foreground, back from Alipay, pull to refresh). Read only.
    func refreshOrder() async {
        guard let engine, !checkoutBusy, let record = checkout, record.phase != .none else { return }
        await perform(progress:"正在核对订单…") {
            record.phase == .paying ? try await engine.returnedFromPayment() : try await engine.refresh()
        }
    }

    // MARK: Order + payment

    var mayImport: Bool { machineChangeRefusal == nil }
    /// Why the machine can't change now (an open order, or a read or order step running), or nil.
    private var machineChangeRefusal: WasherSetupRefusal? {
        WasherSetupRefusal.check(orderOpen:(checkout?.phase ?? LaundryPhase.none) != LaundryPhase.none, busy:loading || checkoutBusy)
    }
    var mayCreate: Bool {
        guard engine != nil, configured, !checkoutBusy, !loading, !storageBlocked, issue == nil,
              let snapshot, snapshot.isOrderable else { return false }
        return checkout?.canCreate ?? true
    }
    var mayCancel: Bool { !checkoutBusy && checkout?.canCancel == true }

    /// Whether the app is in front, asked on the main actor right before a 立刻洗衣 pre-start read.
    @Sendable nonisolated static func appInFront() async -> Bool {
        await MainActor.run { UIApplication.shared.applicationState == .active }
    }

    /// 下单 confirmed in the sheet: create, then pay (each sent once by the engine).
    /// `immediate`: 立刻洗衣 was chosen for this order (the engine starts it once after it is paid).
    func createAndPay(_ program: WasherProgram, immediate: Bool = false) async {
        guard mayCreate, let engine, let snapshot else { return }
        let created = await perform(progress:"正在下单…") {
            try await engine.confirmOrder(snapshot, program:program, immediate:immediate)
        }
        guard created, checkout?.canPay == true else {
            if checkout?.notice == .washerChanged { await refresh(force:true) }
            return
        }
        await pay()
    }

    /// 去付款 confirmed in the sheet: first payment, or a re-pay (both confirmations are the sheet).
    func pay() async {
        guard let engine, !checkoutBusy, let record = checkout else { return }
        if record.canPay {
            await perform(progress:"正在打开支付宝…") { try await engine.pay() }
        } else if record.canRepay(at:Date()) {
            await perform(progress:"正在打开支付宝…") {
                _ = try await engine.requestRepay()
                return try await engine.confirmRepay()
            }
        }
    }

    func cancelOrder() async {
        guard mayCancel, let engine else { return }
        await perform(progress:nil) { try await engine.cancel() }
        await refresh(force:true)
    }

    /// 核对洗衣订单 on a 52 order: the user checked U净; clear the attention state.
    func checkFailedOrder() async {
        guard let engine, checkout?.phase == .attention else { await refreshOrder(); return }
        await perform(progress:nil) { try await engine.acknowledge() }
    }

    /// Reconcile found nothing and the user checked U净.
    func resolveManually() async {
        guard let engine, checkout?.canResolveManually == true else {
            // The last lookup no longer says there is no order: say so instead of doing nothing.
            checkoutIssue = Self.engineText(LaundryEngineError.notAllowed)
            return
        }
        await perform(progress:nil) { try await engine.resolveManually() }
    }

    @discardableResult
    private func perform(progress: String?, _ action: () async throws -> LaundryCheckout) async -> Bool {
        checkoutBusy = true; checkoutIssue = nil; checkoutProgress = progress
        defer { checkoutBusy = false; checkoutProgress = nil }
        do {
            let next = try await action()
            apply(next)
            if next.notice == .sessionExpired { sessionExpired = true }
            checkoutIssue = Self.noticeText(next.notice)
            return next.notice == nil
        } catch {
            if let engine { storageBlocked = await engine.storageBlocked }
            if UjingAccountText.isExpired(error) { sessionExpired = true }
            checkoutIssue = Self.engineText(error)
            return false
        }
    }

    // MARK: Live Activity / reminder

    /// Recomputes the laundry Live Activity from the current facts (also on foreground, for the minutes).
    /// While the order runs, schedules one read-only order re-read a minute after the expected end so a
    /// finished wash is noticed even when the laundry page is closed.
    func syncActivity() {
        // Off: nothing on the lock screen and no laundry reminder (empty facts end / cancel them).
        let facts = schoolEnabled ? LaundryFacts(model:self) : LaundryFacts()
        if !schoolEnabled { activities?.endAll() }
        activities?.sync(facts:facts)
        reminders.syncLaundry(facts:facts)
        syncStartWatch()
        var end: Date?
        if case .running(let value) = facts.phase() { end = value }
        guard end != endCheck?.end else { return }
        endCheck?.task.cancel(); endCheck = nil
        guard let end else { return }
        endCheck = (end, Task { [weak self] in
            do { try await Task.sleep(for:.seconds(max(0, end.timeIntervalSinceNow) + 60)) } catch { return }
            await self?.refreshOrder()
        })
    }

    /// Paid but not washing with a known end: re-read every `LaundryFollowUp.interval` for a few
    /// minutes, only while the app is in front (read only). Coming back to the app reads it anyway.
    private func syncStartWatch() {
        let since = schoolEnabled ? checkout?.waitingSince : nil
        guard since != startWatch?.since else { return }
        startWatch?.task.cancel(); startWatch = nil
        guard let since else { return }
        startWatch = (since, Task { [weak self] in
            var attempt: Date?
            while true {
                guard let record = self?.checkout,
                      let delay = LaundryFollowUp.nextRead(record, lastAttempt:attempt, now:Date()) else { return }
                do { try await Task.sleep(for:.seconds(delay)) } catch { return }
                attempt = Date()
                guard let self else { return }
                if UIApplication.shared.applicationState == .active { await self.refreshOrder() }
            }
        })
    }

    // MARK: Copy

    var deviceStateText: String {
        if let checkout, checkout.phase != .none { return LaundryDisplay(checkout).title }
        return snapshot?.stateLabel ?? "待查询"
    }

    static let uncertainText = "还没确认订单结果。先下拉刷新核对，别重复下单或付款。"

    static func noticeText(_ notice: LaundryNotice?) -> String? {
        switch notice {
        case nil: return nil
        case .refused(let e)?, .readFailed(let e)?: return e.userMessage
        case .sessionExpired?: return UjingAccountText.expired
        case .washerChanged?: return "机器或价格变了，刷新一下再下单。"
        case .priceChanged?: return "U净 的订单价格比你确认的高，没去付款。取消这笔再重新下单。"
        case .orderMismatch?: return "U净 回的订单对不上，先去 U净 App 里看看。"
        case .orderNotFound?: return "没找到这台机器上的订单。去 U净 App 里看看，确认没有再清除。"
        case .noPayChannel?: return "这笔订单没有可用的支付宝付款方式。"
        case .launchRefused?: return "U净 给的付款链接不对，没有打开。"
        case .launchFailed?: return "支付宝没打开。订单还留着，等一下再去付。"
        case .paymentNotConfirmed?: return "还没确认这笔付成功没有。先下拉刷新核对，别重复付款。"
        case .cancelUnconfirmed?: return "还没确认订单取消了没有，下拉刷新看看。"
        case .cancelNotAllowed?: return "这笔订单已经付过了，取消不了。"
        }
    }

    static func engineText(_ error: Error) -> String {
        if UjingAccountText.isExpired(error) { return UjingAccountText.expired }
        if let error = error as? LaundryEngineError { return error.message }
        return (error as? AppReset.InProgress)?.errorDescription ?? message(error) ?? uncertainText
    }

    /// A machine read failed: an expired login says so and offers 「重新登录 U净」.
    private func readText(_ error: Error) -> String? {
        if UjingAccountText.isExpired(error) { sessionExpired = true; return UjingAccountText.expired }
        return Self.message(error)
    }

    private static func message(_ error: Error) -> String? {
        (error as? ServiceError)?.userMessage
    }
}
