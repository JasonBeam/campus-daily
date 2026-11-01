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
            let engine = try LaundryEngine(api:client, vault:AppEnvironment.laundryVault, launcher:AlipayPaymentLauncher(),
                                           hooks:LaundryEngineHooks(), resetMarker:AppResetter.marker)
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

    func login(mobile: String, code: String) async throws {
        guard mayImport else { throw LaundryEngineError.busy }
        let device = device
        let signedIn = try await UjingClient(http:AppEnvironment.laundryHTTP, device:device).login(mobile:mobile, code:code)
        let item = UjingAccountItem(mobileID:device.mobileID, account:signedIn)
        try AppEnvironment.laundryVault.saveAccountItem(item)
        account = item
        accountConnected = true
        configured = selectedMachine != nil
        issue = nil; lastAttempt = nil
        rebuildEngine()
    }

    func signOut() {
        guard mayImport else { return }
        try? AppEnvironment.laundryVault.saveAccountItem(account.map { UjingAccountItem(mobileID:$0.mobileID) })
        account = account.map { UjingAccountItem(mobileID:$0.mobileID) }
        accountConnected = false; configured = false; snapshot = nil
        rebuildEngine()
    }

    /// After a reset cleared the stores: no U净 login, machines or order; the switch back on.
    func reloadAfterReset() {
        endCheck?.task.cancel(); endCheck = nil
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
        guard mayImport else { issue = "先核对已有洗衣订单。"; return }
        guard accountConnected else { issue = "先登录 U净，再添加洗衣机。"; return }
        guard UjingInput.isWasherQR(qrCode) else { issue = "没认出这台洗衣机，换个角度再扫一次。"; return }
        loading = true; issue = nil; candidate = nil
        defer { loading = false }
        do { candidate = try await client.washer(qr:qrCode) }
        catch { issue = Self.message(error) ?? "没认出这台洗衣机，换个角度再扫一次。" }
    }

    func savePreparedMachine(name: String) throws {
        guard mayImport, let value = candidate else { throw LaundryEngineError.busy }
        let alias = name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !alias.isEmpty, alias.count <= 40, alias.rangeOfCharacter(from:.controlCharacters) == nil else { throw LaundryEngineError.notAllowed }
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

    func selectMachine(_ item: SavedWasher) throws {
        guard mayImport, savedMachines.contains(where:{ $0.id == item.id }) else { throw LaundryEngineError.busy }
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

    var mayImport: Bool { !loading && !checkoutBusy && (checkout?.phase ?? LaundryPhase.none) == LaundryPhase.none }
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
        guard let engine, checkout?.canResolveManually == true else { return }
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
