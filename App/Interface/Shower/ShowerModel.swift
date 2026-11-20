import Foundation
import Combine
import Core

/// Resolves the money calls at call time, so the engine survives a profile import.
/// No gateway = a definite local refusal (nothing was sent, nothing issued).
final class ShowerGatewayBox: ShowerGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var gateway: ShowerGateway?
    var current: ShowerGateway? {
        get { lock.withLock { gateway } }
        set { lock.withLock { gateway = newValue } }
    }
    var isAvailable: Bool { current != nil }
    func authorize(_ binding: ShowerBinding, frame: Data) async throws -> ShowerAuthorization {
        guard let current else { throw ServiceError.badRequest(.lxt6) }
        return try await current.authorize(binding, frame:frame)
    }
    func settle(_ binding: ShowerBinding, frame: Data) async throws -> ShowerReceipt {
        guard let current else { throw ServiceError.badRequest(.lxt6) }
        return try await current.settle(binding, frame:frame)
    }
}

/// Where the hot-water platform profile comes from (bundled / imported `.waterconfig`), under
/// the services' `applicationSupport`. Services without files (the sample's) have no profile.
enum ShowerProfileFiles {
    static func importedURL(in support: URL) -> URL {
        support.appendingPathComponent("Water", isDirectory:true).appendingPathComponent(ShowerProfileLoader.importedFileName)
    }
    /// The imported profile if usable, else the bundled one.
    static func localProfile(in support: URL?) async -> ShowerPlatformProfile? {
        guard let support else { return nil }
        return ShowerProfileLoader.localProfile(imported: {
            let url = importedURL(in:support)
            return FileManager.default.fileExists(atPath:url.path) ? try Data(contentsOf:url) : nil
        }, bundled: {
            guard let url = Bundle.main.url(forResource:"CampusWaterPlatform", withExtension:"json") else { return nil }
            return try Data(contentsOf:url)
        })
    }
}

/// UI state over `ShowerEngine`. The engine owns the session; this class only forwards taps and
/// mirrors its state (home, detail page, Live Activity, reminder). Runs on the `CampusServices`
/// it is given: the live app's (`shared`), or a sample's, which hold no real session.
@MainActor final class ShowerModel: ObservableObject {
    static let shared = ShowerModel(services:AppEnvironment.live, reminders:.shared, activities:.shared, gate:liveGate)
    /// Between the live hot water and 「先看看示例」 (`LiveShowerGate`): the sample opens only over
    /// this model's record at rest, and no start begins while it is shown.
    static let liveGate = LiveShowerGate()
    /// The live model's gate; nil for a sample's, which holds no real session.
    private let gate: LiveShowerGate?
    /// How far the saved shower record has been read.
    enum RecordLoad: Equatable { case notLoaded, loaded, failed }
    private(set) var recordLoad = RecordLoad.notLoaded
    private let services: CampusServices
    private let reminders: Reminders
    /// The lock screen's 洗澡中; nil for a sample's.
    private let activities: ShowerActivityController?
    @Published private(set) var state = ShowerState.idle {
        didSet { if state != oldValue { pageEvent(.record(state)) } }
    }
    /// The full-screen shower page: up or not, and the taps it waits on (`ShowerPageFlow`).
    @Published var page = ShowerPageFlow(record:.idle)
    /// Bumped by a tap that wants the page on screen, even when it is already marked up: the
    /// home screen brings it up (closing what covers it first).
    @Published var pageWanted = 0
    /// The running start, so an accepted 取消 can cut the Bluetooth connect short.
    var startTask: Task<Void, Never>?
    /// The start `startTask` runs (`ShowerStartIntent.id`): only it may clear the task.
    var startTaskID: UUID?
    /// The start whose page effect the page shows as starting: only its return ends that.
    var pageStartID: UUID?
    /// The one explicit start in progress, from the tap (or Siri) until its engine call returned,
    /// also while it waits for the explainer or the Bluetooth permission (`ShowerModel+Start`).
    @Published var startSlot: ShowerStartIntent?
    /// Bumped by everything that takes starts back (`invalidateStarts`): a start tapped before
    /// it never runs.
    var startGeneration = 0
    /// The Bluetooth permission request of the slot's start.
    var permissionTask: Task<Void, Never>?
    /// Whether the app may use Bluetooth, read without creating a Bluetooth manager.
    let bluetoothAccess: BluetoothAccess
    /// The words of 「找到了，是你宿舍的水控。」 while shown (1.5 s after a first check matched).
    @Published var checkToastShown = false
    @Published private(set) var binding: ShowerBinding?
    @Published private(set) var profile: ShowerPlatformProfile?
    /// The launch's profile load has finished: before it, `profile` is nil without being missing.
    @Published private(set) var profileLoaded = false
    @Published private(set) var busy = false {
        didSet { if oldValue, !busy, rebuildPending { rebuildPending = false; rebuildEngine() } }
    }
    /// Returns once nothing is in flight (at once when nothing is).
    func untilIdle() async {
        for await value in $busy.values where !value { return }
    }
    /// A rebuild (after a profile import, say) came while something was in flight: it runs once
    /// that is done, so 结束 isn't left without the new profile's gateway.
    private var rebuildPending = false
    /// Last action's message (nil = nothing to say).
    @Published private(set) var message: String?
    @Published private(set) var storageBlocked = false
    /// The saved shower record is there but can't be decoded (another build wrote it): a
    /// relaunch doesn't help, the school's record says what happened.
    @Published private(set) var recordUnreadable = false
    /// The showers a next use kept, read-only; nil when none are kept or they can't be read.
    @Published private(set) var retained: ShowerRetainedSummary?
    #if DEBUG
    /// campusdaily://demo/...-kept: synthetic kept showers the demo pages show instead.
    @Published var demoRetained: ShowerRetainedSummary?
    /// campusdaily://demo/sh-kept-list: 暖橙's 热水洗澡 opens its kept list once on appearing.
    var demoRetainedListOpen = false
    /// campusdaily://demo/sh-denied-final: the refused face without its retry.
    @Published var demoDeniedFinal = false
    /// campusdaily://demo/sh-detail-kept: 暖橙's 热水洗澡 drawn set up and idle in this dorm
    /// (no binding behind it; nothing connects).
    @Published var demoReadyDorm: String?
    /// campusdaily://demo/sh-detail-block-...: the greyed-out 开始洗澡 with this reason (no engine).
    @Published var demoStartBlock: ShowerStartBlock?
    /// campusdaily://demo/sh-detail-ready / -run / -done: the record 暖橙's 热水洗澡 reads instead
    /// of this model's (drawn set up, with `demoReadyDorm`; nothing connects).
    @Published var demoDetailRecord: ShowerState?
    #endif
    /// The campus card's balance a start goes by, pushed by `CampusModel` (`noteBalance`); nil
    /// when it can't be trusted.
    @Published private(set) var balance: ShowerBalance?
    /// Debt is allowed on this phone: a balance below zero doesn't refuse a start.
    @Published private(set) var allowsDebt: Bool
    /// Login attempts that may change who is signed in (`holdForLogin`): no new start meanwhile.
    @Published private(set) var loginHolds: Set<UUID> = []
    @Published private(set) var residenceReviewRequired: Bool
    /// The review is there because the last 退出登录 did not complete (the same person is still
    /// signed in), not because of an account switch or a sign-out that went through.
    private(set) var reviewAfterFailedSignOut: Bool
    @Published private(set) var verifiedDevice: VerifiedShowerDevice?
    @Published private(set) var inspectionStatus: String?
    @Published private(set) var inspecting = false
    /// The last check reached a controller that was in use, so it could not say whose it is.
    @Published private(set) var inspectionFoundBusy = false
    /// What the last 核对 found (the first-run guide's controller step shows it its own way).
    @Published private(set) var inspectionOutcome: InspectionOutcome?
    enum InspectionOutcome: Equatable {
        case verified, notFound, bluetoothOff, inUse, otherMachine
        /// Anything else, with the troubleshooting text.
        case failed(String)
    }
    private(set) var engine: ShowerEngine?
    private var observer: Task<Void, Never>?
    private let gateway = ShowerGatewayBox()
    /// The services' Bluetooth, for the read-only controller check; nil when they have no radio (the sample's).
    private var bluetooth: (any ShowerInspectingTransport)? { services.showerTransport as? any ShowerInspectingTransport }
    private var syncGate = ShowerSyncGate()
    /// What the 「还在计时」 reminder counts from (`ShowerReminderStart`).
    private var reminderStart: Date?

    init(services: CampusServices, reminders: Reminders, activities: ShowerActivityController?, gate: LiveShowerGate? = nil,
         bluetoothAccess: BluetoothAccess? = nil) {
        self.services = services
        allowsDebt = ShowerStartOverrideStore(store:services.secureStore).isOn
        self.bluetoothAccess = bluetoothAccess ?? BluetoothAccessFor.transport(services.showerTransport)
        self.reminders = reminders
        self.activities = activities
        self.gate = gate
        residenceReviewRequired = services.defaults.bool(forKey:PreferenceKey.showerNeedsResidenceReview)
        reviewAfterFailedSignOut = services.defaults.bool(forKey:PreferenceKey.showerReviewAfterFailedSignOut)
        // What older builds' 导出热水诊断 kept on the phone; nothing writes it any more.
        if let support = services.applicationSupport {
            RetiredDiagnostics.removeLeftovers(store:services.secureStore, applicationSupport:support,
                                               temporary:FileManager.default.temporaryDirectory)
        }
        binding = (try? services.showerVault.binding()) ?? nil
        loadRecord()
        page = ShowerPageFlow(record:state)
        gate?.record = { [weak self] in self?.gateRecord ?? .notLoaded }
        Task { await reloadProfile() }
    }

    /// Reads the saved record into `state`. A read that fails is kept as such (`recordLoad`),
    /// not taken for "no shower": the sample stays shut over it.
    private func loadRecord() {
        refreshRetained()
        do {
            if let persisted = try services.showerVault.showerState() { state = ShowerReducer.restore(persisted) }
            recordLoad = .loaded
        } catch {
            recordLoad = .failed
        }
    }

    /// The record as `LiveShowerGate` sees it.
    var gateRecord: LiveShowerGate.Record {
        switch recordLoad {
        case .notLoaded: return .notLoaded
        case .failed: return .unreadable
        case .loaded: return recordUnreadable || storageBlocked ? .unreadable : .known(state)
        }
    }

    // MARK: Balance

    /// The balance the gate goes by (nil: unknown, a start goes). Turning it below zero takes
    /// back a start whose authorize request hasn't left, in the same step.
    func noteBalance(_ value: ShowerBalance?) {
        let before = balanceBlocks
        balance = value
        if !before, balanceBlocks { revokeUnsentStart() }
    }

    /// Debt allowed on this phone, kept in the Keychain. Turned on only once it is stored;
    /// turned off here at once, also when the Keychain refuses.
    /// Returns whether it was stored. Red-phase stub: a turn-off always says so.
    @discardableResult
    func setAllowsDebt(_ value: Bool) -> Bool {
        let store = ShowerStartOverrideStore(store:services.secureStore)
        if value {
            guard (try? store.set(true)) != nil else { return false }
        } else {
            try? store.set(false)
        }
        let before = balanceBlocks
        allowsDebt = value
        if !before, balanceBlocks { revokeUnsentStart() }
        return true
    }

    /// The phrase typed after the five taps on the version: allows debt when it matches,
    /// says nothing otherwise.
    func tryUnlock(_ input: String, digest: String = ShowerStartOverride.digest) {
        guard ShowerStartOverride.matches(input, digest:digest) else { return }
        setAllowsDebt(true)
    }

    /// A start is refused for the balance (`ShowerBalanceGate.blocks`).
    var balanceBlocks: Bool { ShowerBalanceGate.blocks(balance, allowsDebt:allowsDebt) }

    /// Why 开始下一次洗澡 is greyed out on the stopped page: the balance, when nothing else holds it.
    var nextBlock: ShowerStartBlock? { balanceBlocks && nextReady ? .balanceNegative : nil }

    /// A login that may change who is signed in begins (`id`: its attempt): no new start from
    /// here, and a start whose authorize request hasn't left is taken back.
    func holdForLogin(_ id: UUID) {
        loginHolds.insert(id)
        revokeUnsentStart()
    }

    /// That attempt is over (the same person, nothing written, or its clean-up has taken over).
    /// Only its own hold goes; a start taken back stays taken back.
    func releaseLoginHold(_ id: UUID) { loginHolds.remove(id) }

    /// Takes back the start in the slot unless its authorize request already left
    /// (`ShowerStartPermit.revoke()` false: the start goes on as it would have). One waiting on
    /// the explainer goes; one waiting on the system alert ends when it is answered
    /// (`stillHolds`); one running stops before its authorize request (the engine's consume).
    func revokeUnsentStart() {
        guard let slot = startSlot, slot.permit.revoke() else { return }
        switch slot.phase {
        case .awaitingConfirm: startSlot = nil
        case .awaitingPermission: break
        case .starting: if slot.firstCheck { pageEvent(.firstCheckWithdrawn) }
        }
    }

    // MARK: Derived state (what the views read)

    var configured: Bool { binding != nil }
    /// The build has no usable profile (neither bundled nor imported).
    var platformMissing: Bool { binding != nil && profile == nil }
    var mayStart: Bool {
        ShowerLinkRule.mayStart(state, ready:configured && !platformMissing && !residenceReviewRequired && engine != nil && !storageBlocked,
                                busy:busy || !loginHolds.isEmpty, inspecting:inspecting) && !balanceBlocks
    }
    /// Why 开始洗澡 is greyed out (`ShowerStartBlock`): nil exactly when `mayStart`.
    var startBlock: ShowerStartBlock? {
        #if DEBUG
        if let demoStartBlock { return demoStartBlock }
        // A demo drawn set up and idle: 开始洗澡 as it would be.
        if demoReadyDorm != nil { return nil }
        #endif
        return ShowerStartBlock.of(.init(configured:configured, profileLoaded:profileLoaded, platformMissing:platformMissing,
                                         residenceReview:residenceReviewRequired, failedSignOut:reviewAfterFailedSignOut,
                                         recordUnreadable:recordUnreadable, storageBlocked:storageBlocked, engineReady:engine != nil,
                                         inspecting:inspecting, busy:busy || !loginHolds.isEmpty, canStart:state.canStart,
                                         balanceBlocked:balanceBlocks))
    }
    /// Not without a platform profile: the water would close with no way to settle it.
    var mayFinish: Bool { configured && !platformMissing && engine != nil && !busy && !storageBlocked && state.canFinish }
    /// 检查水控状态: while water may run, and after a close that may not have taken.
    var mayReview: Bool { configured && engine != nil && !busy && !storageBlocked && state.canReview }
    /// 开始下一次洗澡 over a shower that is over (`ShowerState.showerOver`): the record is kept,
    /// never settled again.
    var mayStartNext: Bool {
        #if DEBUG
        // Demo records have no engine behind them: the button is drawn as it would be.
        if engine == nil, binding == nil, page.record.canStartNext, page.record.showerOver { return true }
        #endif
        return nextReady && !balanceBlocks
    }
    /// 开始下一次洗澡 as far as everything but the balance goes.
    private var nextReady: Bool {
        configured && !platformMissing && !residenceReviewRequired && engine != nil && !busy && loginHolds.isEmpty && !storageBlocked
            && !inspecting && state.canStartNext
    }
    /// Binding / profile may change only with no session that could still be open or charged.
    var mayImport: Bool { ShowerImportRule.mayImport(state, busy:busy, storageBlocked:storageBlocked) }
    /// The dorm may be set (again): as `mayImport`, and also over a shower that is over and waits
    /// for its check while the binding is a person's who signed out or was replaced. 开始下一次洗澡
    /// is refused then, so nothing else could replace that binding; `saveBinding` keeps the record.
    var mayRebind: Bool {
        mayImport || (residenceReviewRequired && !busy && !storageBlocked && state.canStartNext)
    }
    /// 导入热水配置: also while a shower waits on a missing profile (nothing to replace; it is
    /// what 结束 and 再结算一次 need).
    var mayImportProfile: Bool {
        ShowerImportRule.mayImportProfile(state, profileLoaded:profileLoaded, profileMissing:platformMissing, busy:busy, storageBlocked:storageBlocked)
    }
    /// Why the controller check can't run now (a shower open, or one waiting for its check);
    /// nil when it can.
    var inspectionBlockedText: String? {
        if mayImport { return nil }
        if storageBlocked { return status }
        if state.showerOver { return ShowerPageText.stoppedNote }
        return Self.inspectionShoweringText
    }
    /// A shower that is over is not one (stopped on the controller, or kept with its outcome
    /// unknown): the school settles it.
    var problem: Bool { storageBlocked }
    var sessionStarted: Date? { state.startedAt }
    var lastEnded: Date? { state.phase == .done ? state.endedAt : nil }
    var lastCost: Decimal? { (state.phase == .done ? state.receipt : state.lastReceipt)?.amount?.yuan }
    /// Line under the headline on the hot-water page.
    var status: String {
        if recordUnreadable { return Self.recordUnreadableText }
        if storageBlocked { return "这台手机暂时存不了热水记录，重启 App 后再试。" }
        if let message { return message }
        let unsure = ShowerUnsureReason.of(state)
        if state.showerOver { return unsure.map(ShowerUnsureText.warm) ?? ShowerPageText.stoppedNote }
        switch state.phase {
        case .failed: return ShowerDisplay.title(state)
        case .writePending: return unsure.map(ShowerUnsureText.warm) ?? ShowerDisplay.writeUnconfirmedHint
        default: break
        }
        if !configured { return "选好宿舍后就能用热水。" }
        if platformMissing { return Self.platformMissingText }
        return ""
    }
    nonisolated static let platformMissingText = ShowerActionFailure.platformMissingText
    static let recordUnreadableText = "读不到热水记录。去校园卡记录里看看这次扣了没有，扣费要 1 小时左右才出现。"

    // MARK: Setup

    func reloadProfile() async {
        profile = await ShowerProfileFiles.localProfile(in:services.applicationSupport)
        profileLoaded = true
        rebuildEngine()
    }

    /// (Re)creates the engine for the current binding. Only while nothing is in flight.
    private func rebuildEngine() {
        guard !busy else { rebuildPending = true; return }
        refreshRetained()
        observer?.cancel(); observer = nil; engine = nil
        syncGate.reset()
        recordUnreadable = false
        guard binding != nil else {
            // No engine to report it: the restored state is this run's first, and the lock
            // screen and the reminder follow it like an engine's first report.
            do {
                apply((try services.showerVault.showerState()).map(ShowerReducer.restore) ?? .idle)
                recordLoad = .loaded
            } catch {
                apply(.idle)
                recordLoad = .failed
            }
            return
        }
        let bleName: String
        if let profile {
            bleName = profile.bleName
            gateway.current = services.showerGateway(profile:profile)
        } else {
            bleName = ""
            gateway.current = nil
        }
        do {
            let engine = try services.showerEngine(gateway:gateway, bleName:bleName)
            self.engine = engine
            // The engine read the record: the one it reports is the one to go by, and until
            // its first report is mirrored here nothing is known (the sample stays shut).
            recordLoad = .notLoaded
            observer = Task { [weak self] in
                let blocked = await engine.storageBlocked
                self?.storageBlocked = blocked
                for await next in await engine.updates() {
                    guard let self else { return }
                    self.apply(next)
                    self.storageBlocked = await engine.storageBlocked
                    self.recordLoad = .loaded
                }
            }
        } catch {
            // The engine could not read the record (or keep it): nothing is known of it.
            recordLoad = .failed
            storageBlocked = true
            recordUnreadable = (error as? ShowerEngineError) == .unreadableRecord
            if recordUnreadable {
                // No session to follow: a 洗澡中 left on the lock screen (its 结束 would only be
                // refused) and the 「还在计时」 reminder go.
                activities?.sync(state:.idle)
                reminders.syncShower(started:nil)
            }
        }
    }

    /// Reads the kept showers again (nothing is written). None while the binding waits for the
    /// dorm to be set again: it is then the binding of a person who signed out or was replaced.
    private func refreshRetained() {
        retained = residenceReviewRequired ? nil : ShowerRetainedSummary.read(services.showerVault)
    }

    private func apply(_ next: ShowerState) {
        let old = state
        state = next
        reminderStart = ShowerReminderStart.next(next, after:old, current:reminderStart, now:Date())
        if syncGate.shouldSync(next, after:old) {
            activities?.sync(state:next)
            reminders.syncShower(started:reminderStart)
        }
    }

    /// The kept showers a page shows: the live model's, or nil on a demo page (DEBUG: a demo's).
    func retainedShown(live: Bool) -> ShowerRetainedSummary? {
        #if DEBUG
        if let demoRetained { return demoRetained }
        #endif
        return live ? retained : nil
    }

    /// The refused face offers 开始洗澡 / 再试一次 in place: nothing was issued.
    var deniedRetryable: Bool {
        #if DEBUG
        if demoDeniedFinal { return false }
        #endif
        return page.record.canStart
    }

    #if DEBUG
    /// campusdaily://demo/seed/shower-running: a synthetic running record (no binding, so no
    /// engine and nothing sent), saved in this model's own vault, to check that a sample started
    /// over it never shows or reaches it. Cleared by 重置校日常.
    func demoSeedRunningRecord() {
        let record = ShowerState(phase:.running, machineID:"AABBCC", peripheralID:"SYNTHETIC",
                                 startedAt:Date().addingTimeInterval(-6 * 60))
        guard (try? services.showerVault.saveShowerState(record)) != nil else { return }
        let restored = ShowerReducer.restore(record)
        page = ShowerPageFlow(record:restored)
        apply(restored)
    }
    #endif

    /// After a reset cleared the stores: no binding, no record, bundled profile only.
    func reloadAfterReset() async {
        allowsDebt = ShowerStartOverrideStore(store:services.secureStore).isOn
        balance = nil
        binding = (try? services.showerVault.binding()) ?? nil
        residenceReviewRequired = services.defaults.bool(forKey:PreferenceKey.showerNeedsResidenceReview)
        reviewAfterFailedSignOut = services.defaults.bool(forKey:PreferenceKey.showerReviewAfterFailedSignOut)
        verifiedDevice = nil; inspectionStatus = nil; inspectionFoundBusy = false; inspectionOutcome = nil; message = nil
        await reloadProfile()
        activities?.sync(state:state)
        reminders.syncShower(started:nil)
    }

    /// Onboarding saved a binding (dorm + controller). Refused while a controller check runs.
    func saveBinding(_ value: ShowerBinding) throws {
        try ShowerBinding.checkMayReplace(mayChange:mayRebind, checking:inspecting)
        // Another dorm (or person): no start tapped for the old one runs.
        invalidateStarts()
        var value = value
        // Re-binding the same machine keeps the controller already verified for it.
        if value.peripheralID == nil, let old = binding, old.machineId == value.machineId { value.peripheralID = old.peripheralID }
        // Over a shower that waits for its check: kept first (read back, under the old binding,
        // so it stays its student's), as 开始下一次洗澡 keeps it; only then is its place freed.
        let keepsRecord = !mayImport
        if keepsRecord {
            try services.showerVault.retainShower(state.persistable)
            try services.showerVault.saveShowerState(nil)
        }
        do { try services.showerVault.saveBinding(value) }
        catch {
            // The record's place is free already: show that, under the old binding.
            if keepsRecord { rebuildEngine() }
            throw error
        }
        binding = value
        verifiedDevice = nil
        if residenceReviewRequired { setResidenceReview(false) }
        rebuildEngine()
    }

    /// The school login changed to another person: the binding came from the previous
    /// person's school identity. Removed when the record has been read and nothing could be
    /// open; with a session in flight, or a record not read (yet), it stays (so the close can
    /// still be sent) but no new start is allowed until reviewed.
    /// Returns what became of it (`noticed`: there was a binding to set up again).
    func clearBindingForAccountSwitch() -> AccountSwitch.HotWater {
        invalidateStarts()
        // `state` is the default idle until the record is read: that says nothing.
        var recordRead = false
        if case .known = gateRecord { recordRead = true }
        let result = AccountSwitch.clearHotWater(hasBinding:binding != nil, mayClear:recordRead && mayImport) {
            try services.showerVault.saveBinding(nil)
        }
        switch result {
        case .none: break
        case .keptForReview: setResidenceReview(true)
        case .cleared:
            binding = nil; verifiedDevice = nil; inspectionStatus = nil; inspectionFoundBusy = false; inspectionOutcome = nil; message = nil
            if residenceReviewRequired { setResidenceReview(false) }
            rebuildEngine()
        }
        return result
    }

    /// 退出登录 has started: the binding holds the identity of the person signing out, so no new
    /// shower starts with it from here on. It stays (it goes with `clearBindingForAccountSwitch()`
    /// once the sign-out is done; a sign-out that failed leaves it to be set up again).
    func holdForSignOut() {
        invalidateStarts()
        if binding != nil, !residenceReviewRequired { setResidenceReview(true) }
    }

    /// 退出登录 did not complete while hot water was held for it: remembered (also across a
    /// relaunch) so the refusal says to sign out again. True when hot water is held.
    func signOutDidNotComplete() -> Bool {
        guard residenceReviewRequired else { return false }
        setReviewAfterFailedSignOut(true)
        return true
    }

    /// Set or cleared, the review forgets a failed sign-out behind it.
    func setResidenceReview(_ value: Bool) {
        residenceReviewRequired = value
        services.defaults.set(value, forKey:PreferenceKey.showerNeedsResidenceReview)
        setReviewAfterFailedSignOut(false)
        refreshRetained()
    }

    private func setReviewAfterFailedSignOut(_ value: Bool) {
        reviewAfterFailedSignOut = value
        services.defaults.set(value, forKey:PreferenceKey.showerReviewAfterFailedSignOut)
    }

    /// `.waterconfig` import (Settings › 高级). The profile is the shared platform part only.
    func importConfig(_ url: URL) throws {
        guard mayImportProfile else { throw ShowerEngineError.blocked }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf:url)
        _ = try ShowerConfigFile.parse(data, source:.imported(fileName:ShowerProfileLoader.importedFileName))
        guard let support = services.applicationSupport else { throw ShowerEngineError.blocked }
        let target = ShowerProfileFiles.importedURL(in:support)
        // The copy holds the platform secret: its folder is kept out of backups before it is written.
        try ShowerImportFolder.prepare(for:target)
        try data.write(to:target, options:[.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        Task { await reloadProfile() }
    }

    // MARK: Actions

    /// 开始洗澡 / 结束并结算 (home, detail page, Shortcuts, Live Activity). Throws
    /// `ShowerActionFailure` with the real reason when it did not go through.
    @discardableResult func run(start: Bool) async throws -> ShowerActionOutcome {
        start ? try await startFromShortcut(clear:false) : try await run(nil, start:false)
    }

    /// `intent`: the explicit start this runs (`ShowerStartIntent`); a start without one, or
    /// one taken back since its tap, runs nothing.
    @discardableResult func run(_ intent: ShowerStartIntent?, start: Bool) async throws -> ShowerActionOutcome {
        guard let engine, let binding else { throw ShowerActionFailure(unavailableText) }
        if start {
            guard let intent, stillHolds(intent) else { throw ShowerActionFailure(.withdrawn) }
        }
        guard !busy else { throw ShowerActionFailure(.busy) }
        // Over a shower that is over, 开始洗澡 (Siri, Shortcuts) is the page's 开始下一次洗澡.
        let next = start && state.showerOver
        if start {
            guard next ? mayStartNext : mayStart else { throw ShowerActionFailure(startRefusalText) }
        } else {
            guard state.canFinish else { throw ShowerActionFailure(.notAllowed) }
            guard !platformMissing else { message = Self.platformMissingText; throw ShowerActionFailure(.platformMissing) }
        }
        // The sample is not shown, and from here until this step's record is mirrored it doesn't
        // open (`LiveShowerGate`): nothing is awaited between the checks and the claim. 结束 from
        // the Live Activity or Siri leaves the sample first (`LiveShowerFinish`).
        guard claimLiveStep() else { throw ShowerActionFailure(SampleCopy.blocked) }
        if !start { activities?.settling() }
        busy = true; message = nil
        defer {
            busy = false
            // A next use keeps the record it replaces, whether or not it then goes through.
            if next { refreshRetained() }
            liveStepEnded()
        }
        do {
            let permit = intent?.permit ?? ShowerStartPermit()
            let result = next ? try await engine.startOrNext(binding, permit:permit)
                : start ? try await engine.start(binding, permit:permit) : try await engine.finish(binding)
            apply(result)
            if start, let intent, intent.firstCheck { markMatched(intent, result) }
            // The engine saves the verified controller into the stored binding; pick it up so the
            // next start goes to it directly instead of after a relaunch.
            if start, let stored = (try? services.showerVault.binding()) ?? nil, stored.machineId == binding.machineId {
                self.binding = stored
            }
            // In use over a shower that is over: the page says 水控有人在用 itself, Siri its own words.
            message = next && result.waitingForRelease && result.notice == .device(.busy) ? nil : Self.noticeText(result.notice)
            // Back on the timer: the page says why the end did not go through.
            if !start, result.mayBeFlowing { pageEvent(.endNotSent(result.notice)) }
            return try ShowerActionOutcome.after(start:start, result, notice:message).get()
        } catch let failure as ShowerActionFailure {
            throw failure
        } catch {
            // What the engine holds now (a start that got as far as the controller, say), mirrored
            // before the step's claim goes.
            apply(await engine.state)
            storageBlocked = await engine.storageBlocked
            // A start the engine turned down says what waits, from the record it holds now.
            throw ShowerActionFailure.thrown(error, failure:await engine.state.failure, other:AppErrorText.text)
        }
    }

    /// A live step that may reach the controller or the platform begins (`LiveShowerGate`):
    /// false while the sample is shown. The live model only; a sample's has no gate.
    private func claimLiveStep() -> Bool { gate?.claimLiveStep() ?? true }
    private func liveStepEnded() { gate?.liveStepEnded() }

    /// Why there is no engine to run on, for the callers that can't see the page.
    private var unavailableText: String {
        if !configured { return "选好宿舍后就能用热水。" }
        if recordUnreadable { return ShowerActionFailure(.unreadableRecord).message }
        if storageBlocked { return ShowerActionFailure(.storage).message }
        if platformMissing { return Self.platformMissingText }
        return "热水暂时用不了，打开校日常看看。"
    }

    /// Why 开始洗澡 is not allowed now (`mayStart`), for the callers that can't see the page.
    var startRefusalText: String {
        if platformMissing { return Self.platformMissingText }
        if storageBlocked { return ShowerActionFailure(.storage).message }
        if residenceReviewRequired {
            return reviewAfterFailedSignOut ? "上次退出学校账号没完成，热水暂时开不了。去设置里再退一次，或者重新核对宿舍水控。"
                : "学校账号退出或换过，先在校日常里重新核对宿舍水控。"
        }
        if inspecting { return "正在核对水控，等一下再开始。" }
        // A login that may change who is signed in is under way: as for a step already running.
        if !loginHolds.isEmpty { return ShowerActionFailure(.busy).message }
        if let balanceText = balanceRefusal(clear:false) { return balanceText }
        if !state.canStart { return ShowerActionFailure.blockedText(state.failure) }
        return "现在开始不了，打开校日常看看。"
    }

    /// What Siri says when the balance is the only reason a start (or, over a shower that is
    /// over, a next one) can't go; nil otherwise.
    func balanceRefusal(clear: Bool) -> String? {
        let block = state.showerOver ? nextBlock : startBlock
        guard block == .balanceNegative else { return nil }
        return ShowerStartBlock.balanceNegative.text(clear:clear)
    }

    /// Read-only state probe of the session's controller (Settings › 高级 › 检查水控状态).
    func reviewCurrentSession() async {
        guard let engine, let binding, !busy, state.canReview, claimLiveStep() else { return }
        busy = true; defer { busy = false; liveStepEnded() }
        if let result = try? await engine.review(binding) {
            apply(result)
            // Water running after a close that went out: nothing more was sent (it may be theirs).
            let unsureClose = result.phase == .failed && result.failure?.reason.isUnsureClose == true
            message = unsureClose && result.notice == .inUseByOther ? ShowerAuthorText.closeStillRunning
                : Self.noticeText(result.notice) ?? (result.phase == .running ? "水控显示正在用水。" : nil)
        }
    }

    /// When the last automatic check began (whatever it found), for the interval between two.
    private(set) var lastAutoReview: Date?

    /// The automatic check while the app is in front (`ShowerForegroundCheck`): the read-only
    /// probe, over a record `ShowerAutoReview.eligible` allows, once the interval has passed.
    /// Skipped without waiting when anything else is under way or the sample is shown (a skip
    /// is not an attempt); the attempt counts from before the probe, failed or not. Says nothing.
    /// True when a probe went out.
    @discardableResult func autoReviewIfDue(now: Date = Date()) async -> Bool {
        guard let engine, let binding, !busy, ShowerAutoReview.eligible(state),
              ShowerAutoReview.due(lastAttempt: lastAutoReview, now: now), claimLiveStep() else { return false }
        lastAutoReview = now
        busy = true; defer { busy = false; liveStepEnded() }
        if let result = try? await engine.autoReview(binding) {
            apply(result)
        } else {
            apply(await engine.state)
        }
        return true
    }

    /// 再查一次 on the stopped page found in use: a read-only probe; still running goes back to
    /// the timer (the record says so, nil),
    /// otherwise what it found or why it could not look.
    func recheckSession() async -> ShowerRecheckResult? {
        guard let engine, let binding, state.canReview else { return .unavailable }
        guard !busy else { return .busy }
        guard claimLiveStep() else { return .unavailable }
        busy = true; defer { busy = false; liveStepEnded() }
        do {
            let result = try await engine.review(binding)
            apply(result)
            return ShowerRecheckResult(after:result)
        } catch {
            return ShowerRecheckResult(error:error)
        }
    }

    /// 清除这条记录 on an unreadable record, after its confirmation (the user checked the school's
    /// record). Removed only while it still can't be read; then the engine starts over.
    func clearUnreadableRecord() {
        guard recordUnreadable, !busy else { return }
        let removed = try? services.showerVault.clearUnreadableRecord()
        if removed == true {
            rebuildEngine()
        } else if removed == false {
            // Kept: it reads again (another build rewrote it), so the engine can follow it now.
            rebuildEngine()
        }
        // nil: the Keychain refused; the record and the clear button stay.
    }

    /// 开始下一次洗澡 over a shower stopped on the controller (`ShowerEngine.startNext`): the
    /// record is kept as it is, the controller is checked again and a new authorization is asked
    /// for. A controller still in use is let go (the page says 水控有人在用). False when it didn't
    /// go and the page should say why (`message`).
    @discardableResult
    func startNext(_ intent: ShowerStartIntent) async -> Bool {
        guard let engine, let binding, stillHolds(intent), mayStartNext, claimLiveStep() else { return false }
        busy = true; message = nil
        defer { busy = false; liveStepEnded() }
        do {
            let result = try await engine.startNext(binding, permit:intent.permit)
            apply(result)
            refreshRetained()
            if let stored = (try? services.showerVault.binding()) ?? nil, stored.machineId == binding.machineId {
                self.binding = stored
            }
            // In use: the page says 水控有人在用 itself (`ShowerPageFlow.foundInUse`).
            message = result.notice == .device(.busy) ? nil : Self.noticeText(result.notice)
            return message == nil
        } catch {
            storageBlocked = await engine.storageBlocked
            message = ShowerActionFailure.thrown(error, failure:await engine.state.failure, other:AppErrorText.text).message
            apply(await engine.state)
            refreshRetained()
            return false
        }
    }

    func disarmSettleRetry() async {
        guard let engine else { return }
        if let result = try? await engine.disarmSettleRetry() { apply(result) }
    }

    func dismiss(only record: ShowerState? = nil) async {
        guard let engine, !busy else { return }
        if let result = try? await engine.dismiss(only:record) { apply(result) }
    }

    /// Read-only: connect, ask the identity (0xAA), disconnect. Never sent during a session.
    func inspectBluetooth() async {
        guard !inspecting else { return }
        // Only this check's answer counts: an earlier one must not read as found.
        inspectionOutcome = nil
        guard let binding, mayImport, ShowerLinkRule.mayInspect(state, busy:busy, inspecting:inspecting) else { return }
        let bleName = profile?.bleName ?? ""
        guard !bleName.isEmpty else { inspectionStatus = Self.platformMissingText; inspectionOutcome = .failed(Self.platformMissingText); return }
        guard let bluetooth else { inspectionStatus = Self.deviceText(.notFound); inspectionOutcome = .notFound; return }
        inspecting = true; inspectionStatus = nil; verifiedDevice = nil; inspectionFoundBusy = false; inspectionOutcome = nil
        defer { inspecting = false }
        let generation = startGeneration
        do {
            let nearby = try await bluetooth.inspect(bleName:bleName, remembered:binding.peripheralID)
            guard nearby > 0 else { inspectionStatus = Self.deviceText(.notFound); inspectionOutcome = .notFound; return }
            let outcome = try await ShowerInspection.run(transport:bluetooth, bleName:bleName, machineID:binding.machineId,
                                                         remembered:binding.peripheralID) { forgetRemembered($0, for:binding) }
            let id: String
            switch outcome {
            case .unreadable:
                inspectionStatus = Self.deviceText(.malformedFrame); inspectionOutcome = .failed(Self.deviceText(.malformedFrame)); return
            case .otherMachine: inspectionStatus = "附近的水控不是你宿舍的那台。"; inspectionOutcome = .otherMachine; return
            case .busy:
                // An in-use controller does not say which machine it is: nothing was verified.
                inspectionFoundBusy = true
                inspectionStatus = Self.inspectionBusyText
                inspectionOutcome = .inUse
                return
            case .verified(let found): id = found
            }
            verifiedDevice = VerifiedShowerDevice(id:id, name:bleName, machineID:binding.machineId.uppercased(), nearbyCount:nearby, verifiedAt:Date())
            if let proven = outcome.peripheralToRemember { rememberVerified(proven, for:binding) }
            // The number matched: the next start reads it again, under its usual words.
            markMatched(binding, generation:generation)
            inspectionStatus = Self.inspectionVerifiedText
            inspectionOutcome = .verified
        } catch {
            await services.showerTransport.disconnect()
            let device = ShowerEngine.deviceError(error)
            inspectionStatus = Self.deviceText(device)
            switch device {
            case .bluetoothOff: inspectionOutcome = .bluetoothOff
            case .notFound: inspectionOutcome = .notFound
            default: inspectionOutcome = .failed(Self.deviceText(device))
            }
        }
    }

    /// The binding as stored again (`markMatched`).
    func setBinding(_ value: ShowerBinding) { binding = value }
    /// Where the binding is kept (`markMatched`).
    var showerVault: StoredShowerVault { services.showerVault }

    /// The check proved this controller's identity: remember it for the next start.
    private func rememberVerified(_ id: String, for checked: ShowerBinding) {
        guard checked.peripheralID != id, var stored = (try? services.showerVault.binding()) ?? nil,
              stored.machineId == checked.machineId else { return }
        stored.peripheralID = id
        guard (try? services.showerVault.saveBinding(stored)) != nil else { return }
        binding = stored
    }

    private func forgetRemembered(_ id: String, for checked: ShowerBinding) {
        guard var stored = (try? services.showerVault.binding()) ?? nil,
              stored.machineId == checked.machineId, stored.peripheralID == id else { return }
        stored.peripheralID = nil
        guard (try? services.showerVault.saveBinding(stored)) != nil else { return }
        binding = stored
    }

    func show(_ error: Error) { message = AppErrorText.text(error) }

    // MARK: Copy

    static let inspectionVerifiedText = "找到了，是这间的水控。"
    nonisolated static let inspectionShoweringText = "正在洗澡，洗完再核对水控。"
    static let inspectionBusyText = "附近的水控有人在用，现在核对不了是不是这间的。等它空了再试。"

    static func noticeText(_ notice: ShowerNotice?) -> String? {
        switch notice {
        case nil: return nil
        case .device(let e)?: return deviceText(e)
        case .notActive?: return ShowerPageText.stoppedNote
        case .wrongDevice?: return "附近的水控不是你宿舍的那台。"
        case .writeUnconfirmed?: return ShowerDisplay.writeUnconfirmedHint
        case .inUseByOther?: return ShowerPageText.endInUseByOther
        case .waterRunning?: return ShowerPageText.checkWaterRunning
        }
    }

    static func deviceText(_ e: ShowerDeviceError) -> String { e.userText }
}
