import Foundation
import Combine
import UIKit
import Core

/// A washer the user saved by scanning its code (UI preference, not a credential).
struct SavedWasher: Codable, Identifiable, Equatable {
    var id: String
    var qrCode: String
    var name: String
    var savedAt = Date()
}

private struct LaundryEngineHooks: LaundryHooks {
    // The Live Activity and the done reminder follow `LaundryFacts` (LaundryModel.syncActivity).
    func updateActivity(_ plan: LaundryActivityPlan) async {}
    func endActivity() async {}
    func diagnostic(_ event: String) async {}
}

/// UI state over `UjingClient` (login, machine reads) and `LaundryEngine` (order + payment).
/// No ordering or payment rules here: the engine decides what may be sent.
/// Another U净 account tried to sign in while an order placed with the stored one is open.
enum LaundryLoginRefusal: Error { case otherAccount }

@MainActor final class LaundryModel: ObservableObject {
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
    /// 「学校洗衣机」 (Settings / first-run question). Off: laundry hidden everywhere, no reads,
    /// no Live Activity, no reminder; the U净 login and saved machines stay.
    @Published private(set) var schoolEnabled = SchoolLaundryPreference(storage:UserDefaults.standard).isOn
    @Published private(set) var lastOrder: LaundryLastOrder? = {
        UserDefaults.standard.data(forKey:LaundryModel.lastOrderKey).flatMap { try? JSONDecoder().decode(LaundryLastOrder.self, from:$0) }
    }()

    private var account: UjingAccountItem?
    private var engine: LaundryEngine?
    private var observer: Task<Void, Never>?
    private var lastAttempt: Date?
    private var activitySync: AnyCancellable?
    private var endCheck: (end: Date, task: Task<Void, Never>)?
    private var startWatch: (since: Date, task: Task<Void, Never>)?
    private static let machinesKey = PreferenceKey.prefix + "laundry.machines"
    private static let selectedKey = PreferenceKey.prefix + "laundry.selected"
    nonisolated static let lastOrderKey = PreferenceKey.prefix + "laundry.lastOrder"

    init() {
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
        SchoolLaundryPreference(storage:UserDefaults.standard).set(on)
        schoolEnabled = on
        if on { Task { await refresh(force:true) } } else { snapshot = nil; issue = nil; lastAttempt = nil }
        syncActivity()
    }

    // MARK: Account + engine

    /// The install's `x-mobile-id`: a dashed UUID (the client rejects anything else), created once
    /// and saved so the SMS request and the login send the same id.
    private var device: UjingDevice {
        if account == nil, let id = try? AppEnvironment.laundryVault.mobileID() { account = UjingAccountItem(mobileID:id) }
        return UjingDevice(mobileID:account?.mobileID ?? UUID().uuidString, userAgent:AppEnvironment.userAgent)
    }

    private func reloadAccount() {
        do {
            account = try AppEnvironment.laundryVault.accountItem()
            issue = nil
        } catch {
            issue = "解锁手机后再打开校日常。"
        }
        accountConnected = account?.account != nil
        savedMachines = Self.loadMachines()
        selectedMachineID = UserDefaults.standard.string(forKey:Self.selectedKey).flatMap { id in
            savedMachines.contains { $0.id == id } ? id : nil
        } ?? savedMachines.first?.id
        configured = accountConnected && selectedMachine != nil
        rebuildEngine()
    }

    private var selectedMachine: SavedWasher? { savedMachines.first { $0.id == selectedMachineID } }

    private var client: UjingClient {
        if let signedIn = account?.account { return UjingClient(http:AppEnvironment.laundryHTTP, device:device, account:signedIn) }
        return UjingClient(http:AppEnvironment.laundryHTTP, device:device)
    }

    private func rebuildEngine() {
        guard !checkoutBusy else { return }
        observer?.cancel(); observer = nil; engine = nil
        do {
            let engine = try LaundryEngine(api:client, vault:AppEnvironment.laundryVault, launcher:AlipayPaymentLauncher(returned:{ [weak self] in Task { await self?.refreshOrder() } }),
                                           hooks:LaundryEngineHooks(), accountID:account?.account?.id,
                                           resetMarker:AppResetter.marker)
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
            checkout = (try? AppEnvironment.laundryVault.checkout()) ?? nil
        }
    }

    private func apply(_ next: LaundryCheckout) {
        if let id = next.orderID, let draft = next.draft {
            let note = LaundryLastOrder(orderID:id, program:draft.program, machineName:draft.machineName, amount:next.order?.price)
            if note != lastOrder {
                lastOrder = note
                UserDefaults.standard.set(try? JSONEncoder().encode(note), forKey:Self.lastOrderKey)
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
        let signedIn = try await UjingClient(http:AppEnvironment.laundryHTTP, device:device).login(mobile:mobile, code:code)
        guard !loading, !checkoutBusy else { throw LaundryEngineError.busy }
        guard !storageBlocked else { throw LaundryEngineError.storage }
        if let record = checkout, !record.allowsLogin(as:signedIn.id, stored:account?.account?.id) {
            throw LaundryLoginRefusal.otherAccount
        }
        let reread = checkout.map { $0.phase != .none } ?? false
        let clearsLastOrder = LaundryCheckout.clearsLastOrder(record:checkout, signedInAs:signedIn.id, stored:account?.account?.id)
        let item = UjingAccountItem(mobileID:device.mobileID, account:signedIn)
        try AppEnvironment.laundryVault.saveAccountItem(item)
        if clearsLastOrder { forgetLastOrder() }
        account = item
        accountConnected = true
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
        if error is LaundryEngineError { return engineText(error) }
        return (error as? ServiceError)?.userMessage ?? "登录没完成，核对手机号和验证码再试。"
    }

    func signOut() {
        guard mayImport else { return }
        let clearsLastOrder = LaundryCheckout.clearsLastOrder(record:checkout, signedInAs:nil, stored:account?.account?.id)
        try? AppEnvironment.laundryVault.saveAccountItem(account.map { UjingAccountItem(mobileID:$0.mobileID) })
        account = account.map { UjingAccountItem(mobileID:$0.mobileID) }
        accountConnected = false; configured = false; snapshot = nil
        if clearsLastOrder { forgetLastOrder() }
        rebuildEngine()
    }

    /// The finished order's outcome and the last-order note belong to the account that placed
    /// it: they go before the engine is rebuilt from the stored record. Only called with no order
    /// open (`LaundryCheckout.clearsLastOrder`), when the record holds nothing but that outcome.
    private func forgetLastOrder() {
        if checkout?.lastOutcome != nil, (try? AppEnvironment.laundryVault.saveCheckout(nil)) != nil {
            checkout = nil
        }
        lastOrder = nil
        UserDefaults.standard.removeObject(forKey:Self.lastOrderKey)
    }

    /// After a reset cleared the stores: no U净 login, machines or order; the switch back on.
    func reloadAfterReset() {
        endCheck?.task.cancel(); endCheck = nil
        startWatch?.task.cancel(); startWatch = nil
        schoolEnabled = SchoolLaundryPreference(storage:UserDefaults.standard).isOn
        lastOrder = nil; snapshot = nil; candidate = nil; checkout = nil
        issue = nil; checkoutIssue = nil; checkoutProgress = nil; lastAttempt = nil
        account = nil
        reloadAccount()
        LaundryActivityController.shared.endAll()
    }

    // MARK: Machines (WasherSetupView)

    private static func loadMachines() -> [SavedWasher] {
        guard let data = UserDefaults.standard.data(forKey:machinesKey) else { return [] }
        return (try? JSONDecoder().decode([SavedWasher].self, from:data)) ?? []
    }
    private func storeMachines(_ list: [SavedWasher]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey:Self.machinesKey)
        savedMachines = list
    }

    /// Scanned a code: read the machine (scan + programs), keep it as the candidate.
    func prepareMachine(qrCode: String) async {
        if let refusal = machineChangeRefusal { issue = refusal.message; return }
        guard accountConnected else { issue = "先登录 U净，再添加洗衣机。"; return }
        guard UjingInput.isWasherQR(qrCode) else { issue = "没认出这台洗衣机，换个角度再扫一次。"; return }
        loading = true; issue = nil; candidate = nil
        defer { loading = false }
        do { candidate = try await client.washer(qr:qrCode) }
        catch { issue = Self.message(error) ?? "没认出这台洗衣机，换个角度再扫一次。" }
    }

    /// Throws `WasherSetupRefusal`, whose text the page shows.
    func savePreparedMachine(name: String) throws {
        if let refusal = machineChangeRefusal { throw refusal }
        guard let value = candidate else { throw WasherSetupRefusal.nothingToSave }
        let alias = try WasherSetupRefusal.machineName(name).get()
        var list = savedMachines
        if let index = list.firstIndex(where:{ $0.id == value.deviceID }) {
            list[index] = SavedWasher(id:value.deviceID, qrCode:value.qrCode, name:alias, savedAt:list[index].savedAt)
        } else {
            list.append(SavedWasher(id:value.deviceID, qrCode:value.qrCode, name:alias))
        }
        storeMachines(list)
        select(value.deviceID)
        snapshot = value
        candidate = nil; issue = nil; checkoutIssue = nil; lastAttempt = Date()
    }

    /// Throws `WasherSetupRefusal`, whose text the page shows.
    func selectMachine(_ item: SavedWasher) throws {
        if let refusal = machineChangeRefusal { throw refusal }
        guard savedMachines.contains(where:{ $0.id == item.id }) else { throw WasherSetupRefusal.notSaved }
        select(item.id)
        snapshot = nil; issue = nil; checkoutIssue = nil; lastAttempt = nil
    }

    private func select(_ id: String) {
        selectedMachineID = id
        UserDefaults.standard.set(id, forKey:Self.selectedKey)
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
        do { snapshot = try await client.washer(qr:machine.qrCode) }
        catch { issue = Self.message(error) ?? "暂时连不上 U净，先显示上次的状态。" }
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

    /// 下单 confirmed in the sheet: create, then pay (each sent once by the engine).
    func createAndPay(_ program: WasherProgram) async {
        guard mayCreate, let engine, let snapshot else { return }
        let created = await perform(progress:"正在下单…") { try await engine.confirmOrder(snapshot, program:program) }
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
            checkoutIssue = Self.noticeText(next.notice)
            return next.notice == nil
        } catch {
            if let engine { storageBlocked = await engine.storageBlocked }
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
        if !schoolEnabled { LaundryActivityController.shared.endAll() }
        LaundryActivityController.shared.sync(facts:facts)
        Reminders.shared.syncLaundry(facts:facts)
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
        case .sessionExpired?: return "U净 登录过期了，重新登录一下。"
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
        switch error as? LaundryEngineError {
        case .busy?: return "正在处理上一步，稍等一下。"
        case .notAllowed?: return "现在不能这样操作，下拉刷新看看。"
        case .washerChanged?: return "机器或价格变了，刷新一下再下单。"
        case .storage?: return "这台手机暂时存不了洗衣订单，重启 App 后再试。"
        case nil: return (error as? AppReset.InProgress)?.errorDescription ?? message(error) ?? uncertainText
        }
    }

    private static func message(_ error: Error) -> String? {
        (error as? ServiceError)?.userMessage
    }
}
