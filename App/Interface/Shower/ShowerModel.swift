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
    @Published private(set) var residenceReviewRequired: Bool
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
    private var bluetooth: BluetoothTransport? { services.showerTransport as? BluetoothTransport }
    private var syncGate = ShowerSyncGate()
    /// What the 「还在计时」 reminder counts from (`ShowerReminderStart`).
    private var reminderStart: Date?

    init(services: CampusServices, reminders: Reminders, activities: ShowerActivityController?, gate: LiveShowerGate? = nil) {
        self.services = services
        self.reminders = reminders
        self.activities = activities
        self.gate = gate
        residenceReviewRequired = services.defaults.bool(forKey:PreferenceKey.showerNeedsResidenceReview)
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

    // MARK: Derived state (what the views read)

    var configured: Bool { binding != nil }
    /// The build has no usable profile (neither bundled nor imported).
    var platformMissing: Bool { binding != nil && profile == nil }
    var mayStart: Bool {
        ShowerLinkRule.mayStart(state, ready:configured && !platformMissing && !residenceReviewRequired && engine != nil && !storageBlocked,
                                busy:busy, inspecting:inspecting)
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
        return configured && !platformMissing && !residenceReviewRequired && engine != nil && !busy && !storageBlocked && !inspecting
            && state.canStartNext
    }
    /// Binding / profile may change only with no session that could still be open or charged.
    var mayImport: Bool { ShowerImportRule.mayImport(state, busy:busy, storageBlocked:storageBlocked) }
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
        if state.showerOver { return ShowerPageText.stoppedNote }
        switch state.phase {
        case .failed: return ShowerDisplay.failureTitle(state.failure)
        case .writePending: return ShowerDisplay.writeUnconfirmedHint
        default: break
        }
        if !configured { return "选好宿舍后就能用热水。" }
        if platformMissing { return Self.platformMissingText }
        return ""
    }
    nonisolated static let platformMissingText = ShowerActionFailure.platformMissingText
    static let recordUnreadableText = "读不到热水记录。去学校的热水记录里看看这次扣了没有。"

    // MARK: Setup

    func reloadProfile() async {
        profile = await ShowerProfileFiles.localProfile(in:services.applicationSupport)
        profileLoaded = true
        rebuildEngine()
    }

    /// (Re)creates the engine for the current binding. Only while nothing is in flight.
    private func rebuildEngine() {
        guard !busy else { rebuildPending = true; return }
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

    private func apply(_ next: ShowerState) {
        let old = state
        state = next
        reminderStart = ShowerReminderStart.next(next, after:old, current:reminderStart, now:Date())
        if syncGate.shouldSync(next, after:old) {
            activities?.sync(state:next)
            reminders.syncShower(started:reminderStart)
        }
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
        binding = (try? services.showerVault.binding()) ?? nil
        residenceReviewRequired = services.defaults.bool(forKey:PreferenceKey.showerNeedsResidenceReview)
        verifiedDevice = nil; inspectionStatus = nil; inspectionFoundBusy = false; inspectionOutcome = nil; message = nil
        await reloadProfile()
        activities?.sync(state:state)
        reminders.syncShower(started:nil)
    }

    /// Onboarding saved a binding (dorm + controller). Refused while a controller check runs.
    func saveBinding(_ value: ShowerBinding) throws {
        try ShowerBinding.checkMayReplace(mayChange:mayImport, checking:inspecting)
        var value = value
        // Re-binding the same machine keeps the controller already verified for it.
        if value.peripheralID == nil, let old = binding, old.machineId == value.machineId { value.peripheralID = old.peripheralID }
        try services.showerVault.saveBinding(value)
        binding = value
        verifiedDevice = nil
        if residenceReviewRequired { setResidenceReview(false) }
        rebuildEngine()
    }

    /// The school login changed to another person: the binding came from the previous
    /// person's school identity. Removed when nothing could be open; with a session in flight
    /// it stays (so the close can still be sent) but no new start is allowed until reviewed.
    /// Returns what became of it (`noticed`: there was a binding to set up again).
    func clearBindingForAccountSwitch() -> AccountSwitch.HotWater {
        let result = AccountSwitch.clearHotWater(hasBinding:binding != nil, mayClear:mayImport) {
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

    func setResidenceReview(_ value: Bool) {
        residenceReviewRequired = value
        services.defaults.set(value, forKey:PreferenceKey.showerNeedsResidenceReview)
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
        guard let engine, let binding else { throw ShowerActionFailure(unavailableText) }
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
            liveStepEnded()
        }
        do {
            let result = next ? try await engine.startOrNext(binding)
                : start ? try await engine.start(binding) : try await engine.finish(binding)
            apply(result)
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
    private var startRefusalText: String {
        if platformMissing { return Self.platformMissingText }
        if storageBlocked { return ShowerActionFailure(.storage).message }
        if residenceReviewRequired { return "换了学校账号，先在校日常里重新核对宿舍水控。" }
        if inspecting { return "正在核对水控，等一下再开始。" }
        if !state.canStart { return ShowerActionFailure.blockedText(state.failure) }
        return "现在开始不了，打开校日常看看。"
    }

    /// Read-only state probe of the session's controller (Settings › 高级 › 检查水控状态).
    func reviewCurrentSession() async {
        guard let engine, let binding, !busy, state.canReview, claimLiveStep() else { return }
        busy = true; defer { busy = false; liveStepEnded() }
        if let result = try? await engine.review(binding) {
            apply(result)
            message = Self.noticeText(result.notice) ?? (result.phase == .running ? "水控显示正在用水。" : nil)
        }
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
    func startNext() async -> Bool {
        guard let engine, let binding, mayStartNext, claimLiveStep() else { return false }
        busy = true; message = nil
        defer { busy = false; liveStepEnded() }
        do {
            let result = try await engine.startNext(binding)
            apply(result)
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
        }
    }

    static func deviceText(_ e: ShowerDeviceError) -> String { e.userText }
}
