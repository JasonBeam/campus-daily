import Foundation
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
    func authorize(_ binding: ShowerBinding, frame: Data) async throws -> ShowerAuthorization {
        guard let current else { throw ServiceError.badRequest(.lxt6) }
        return try await current.authorize(binding, frame:frame)
    }
    func settle(_ binding: ShowerBinding, frame: Data) async throws -> ShowerReceipt {
        guard let current else { throw ServiceError.badRequest(.lxt6) }
        return try await current.settle(binding, frame:frame)
    }
}

private struct ShowerModelHooks: ShowerHooks {
    func scheduleUnsettledReminder(after seconds: TimeInterval) async {}
    func cancelUnsettledReminder() async {}
    func diagnostic(_ event: String) async { await ShowerDiagnosticReport.record(event) }
}

/// Where the hot-water platform profile comes from (bundled / imported `.waterconfig`).
enum ShowerProfileFiles {
    static var importedURL: URL {
        FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask)[0]
            .appendingPathComponent("Water", isDirectory:true).appendingPathComponent("imported.waterconfig")
    }
    static let loader = ShowerProfileLoader(bundled: {
        guard let url = Bundle.main.url(forResource:"CampusWaterPlatform", withExtension:"json") else { return nil }
        return try Data(contentsOf:url)
    }, imported: { _ in
        let url = ShowerProfileFiles.importedURL
        return FileManager.default.fileExists(atPath:url.path) ? try Data(contentsOf:url) : nil
    })
    static let sources: [ShowerProfileSource] = [.imported(fileName:"imported.waterconfig"), .bundled]
    static func localProfile() async -> ShowerPlatformProfile? {
        if case .success(.local(let profile, _)) = await ShowerProfileResolver.firstUsable(sources, provider:loader) { return profile }
        return nil
    }
}

/// UI state over `ShowerEngine`. The engine owns the session; this class only forwards taps and
/// mirrors its state (home, detail page, Live Activity, reminder).
@MainActor final class ShowerModel: ObservableObject {
    static let shared = ShowerModel()
    @Published private(set) var state = ShowerState.idle {
        didSet { if state != oldValue { pageEvent(.record(state)) } }
    }
    /// The full-screen shower page: up or not, and the taps it waits on (`ShowerPageFlow`).
    @Published var page = ShowerPageFlow(record:.idle)
    /// 去核对 on the page: the home screen opens the 核对 screen.
    @Published var reviewRequested = false
    /// Bumped by a tap that wants the page on screen, even when it is already marked up: the
    /// home screen brings it up (closing what covers it first).
    @Published var pageWanted = 0
    /// The running start, so an accepted 取消 can cut the Bluetooth connect short.
    var startTask: Task<Void, Never>?
    @Published private(set) var binding: ShowerBinding?
    @Published private(set) var profile: ShowerPlatformProfile?
    @Published private(set) var busy = false
    /// Last action's message (nil = nothing to say).
    @Published private(set) var message: String?
    @Published private(set) var storageBlocked = false
    @Published private(set) var residenceReviewRequired = UserDefaults.standard.bool(forKey:PreferenceKey.showerNeedsResidenceReview)
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
    private let bluetooth = BluetoothTransport()
    private var syncGate = ShowerSyncGate()

    init() {
        binding = (try? AppEnvironment.showerVault.binding()) ?? nil
        if let persisted = (try? AppEnvironment.showerVault.showerState()) ?? nil { state = ShowerReducer.restore(persisted) }
        page = ShowerPageFlow(record:state)
        Task { await reloadProfile() }
    }

    // MARK: Derived state (what the views read)

    var configured: Bool { binding != nil }
    var display: ShowerDisplay { ShowerDisplay(state) }
    /// The build has no usable profile (neither bundled nor imported).
    var platformMissing: Bool { binding != nil && profile == nil }
    var mayStart: Bool {
        ShowerLinkRule.mayStart(state, ready:configured && !platformMissing && !residenceReviewRequired && engine != nil && !storageBlocked,
                                busy:busy, inspecting:inspecting)
    }
    var mayFinish: Bool { configured && engine != nil && !busy && !storageBlocked && state.canFinish }
    var mayResolveManually: Bool { engine != nil && !busy && state.canResolveManually }
    var mayRetrySettle: Bool { engine != nil && !busy && state.canRetrySettle }
    /// Binding / profile may change only with no session that could still be open or charged.
    var mayImport: Bool {
        !busy && !storageBlocked && (state.phase == .idle || state.phase == .done || (state.phase == .failed && state.failure?.needsReview == false))
    }
    /// Why the controller check can't run now (a shower open, or one waiting for its check);
    /// nil when it can.
    var inspectionBlockedText: String? {
        if mayImport { return nil }
        if storageBlocked { return status }
        if state.stateReviewRequired || state.failure?.needsReview == true { return Self.inspectionAwaitingCheckText }
        return Self.inspectionShoweringText
    }
    var problem: Bool { state.failure?.needsReview == true || state.stateReviewRequired || storageBlocked }
    /// The close was sent or the settlement is unconfirmed: money may have moved.
    var unresolvedClose: Bool {
        guard state.phase == .failed, let reason = state.failure?.reason else { return false }
        return [.closeUnconfirmed, .settleRefused, .settleUncertain, .settleUnconfirmed].contains(reason)
    }
    var sessionStarted: Date? { state.startedAt }
    var lastEnded: Date? { state.phase == .done ? state.endedAt : nil }
    var lastCost: Decimal? { (state.phase == .done ? state.receipt : state.lastReceipt)?.amount?.yuan }
    /// Line under the headline on the hot-water page.
    var status: String {
        if storageBlocked { return "这台手机暂时存不了热水记录，重启 App 后再试。" }
        if let message { return message }
        if state.stateReviewRequired { return "水控没显示在用水，校日常就没发结束。去学校的热水记录里核对一下这次洗澡。" }
        switch state.phase {
        case .failed: return ShowerDisplay.failureTitle(state.failure)
        case .writePending: return ShowerDisplay.writeUnconfirmedHint
        default: break
        }
        if !configured { return "选好宿舍后就能用热水。" }
        if platformMissing { return Self.platformMissingText }
        return ""
    }
    nonisolated static let platformMissingText = "这个版本没带热水配置，热水暂时用不了。"

    // MARK: Setup

    func reloadProfile() async {
        profile = await ShowerProfileFiles.localProfile()
        rebuildEngine()
    }

    /// (Re)creates the engine for the current binding. Only while nothing is in flight.
    private func rebuildEngine() {
        guard !busy else { return }
        observer?.cancel(); observer = nil; engine = nil
        syncGate.reset()
        guard binding != nil else {
            // No engine to report it: the restored state is this run's first, and the lock
            // screen and the reminder follow it like an engine's first report.
            apply(((try? AppEnvironment.showerVault.showerState()) ?? nil).map(ShowerReducer.restore) ?? .idle)
            return
        }
        let bleName: String
        if let profile {
            bleName = profile.bleName
            gateway.current = LxtClient(http:AppEnvironment.showerHTTP, profile:profile)
        } else {
            bleName = ""
            gateway.current = nil
        }
        do {
            let engine = try ShowerEngine(transport:bluetooth, gateway:gateway, vault:AppEnvironment.showerVault,
                                          configuration:.init(bleName:bleName,
                                                              reminderMinutes:UserDefaults.standard.integer(forKey:ReminderKey.unsettledMinutes)),
                                          hooks:ShowerModelHooks(), resetMarker:AppResetter.marker)
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
        }
    }

    private func apply(_ next: ShowerState) {
        let old = state
        state = next
        if syncGate.shouldSync(next, after:old) {
            ShowerActivityController.shared.sync(state:next)
            Reminders.shared.syncShower(started:next.mayBeFlowing ? next.startedAt : nil)
        }
    }

    /// After a reset cleared the stores: no binding, no record, bundled profile only.
    func reloadAfterReset() async {
        binding = (try? AppEnvironment.showerVault.binding()) ?? nil
        residenceReviewRequired = UserDefaults.standard.bool(forKey:PreferenceKey.showerNeedsResidenceReview)
        verifiedDevice = nil; inspectionStatus = nil; inspectionFoundBusy = false; inspectionOutcome = nil; message = nil
        await reloadProfile()
        ShowerActivityController.shared.sync(state:state)
        Reminders.shared.syncShower(started:nil)
    }

    /// Onboarding saved a binding (dorm + controller). Refused while a controller check runs.
    func saveBinding(_ value: ShowerBinding) throws {
        try ShowerBinding.checkMayReplace(mayChange:mayImport, checking:inspecting)
        var value = value
        // Re-binding the same machine keeps the controller already verified for it.
        if value.peripheralID == nil, let old = binding, old.machineId == value.machineId { value.peripheralID = old.peripheralID }
        try AppEnvironment.showerVault.saveBinding(value)
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
            try AppEnvironment.showerVault.saveBinding(nil)
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
        UserDefaults.standard.set(value, forKey:PreferenceKey.showerNeedsResidenceReview)
    }

    /// `.waterconfig` import (Settings › 高级). The profile is the shared platform part only.
    func importConfig(_ url: URL) throws {
        guard mayImport else { throw ShowerEngineError.blocked }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf:url)
        _ = try ShowerConfigFile.parse(data, source:.imported(fileName:"imported.waterconfig"))
        let target = ShowerProfileFiles.importedURL
        try FileManager.default.createDirectory(at:target.deletingLastPathComponent(), withIntermediateDirectories:true)
        try data.write(to:target, options:[.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        Task { await reloadProfile() }
    }

    // MARK: Actions

    /// 开始洗澡 / 结束并结算 (home, detail page, Shortcuts, Live Activity).
    func run(start: Bool) async throws {
        guard let engine, let binding else { throw ShowerEngineError.notAllowed }
        guard !busy else { throw ShowerEngineError.busy }
        if start {
            guard mayStart else { throw ShowerEngineError.blocked }
        } else {
            guard state.canFinish else { throw ShowerEngineError.notAllowed }
            ShowerActivityController.shared.settling()
        }
        busy = true; message = nil
        defer { busy = false }
        do {
            let result = start ? try await engine.start(binding) : try await engine.finish(binding)
            apply(result)
            // The engine saves the verified controller into the stored binding; pick it up so the
            // next start goes to it directly instead of after a relaunch.
            if start, let stored = (try? AppEnvironment.showerVault.binding()) ?? nil, stored.machineId == binding.machineId {
                self.binding = stored
            }
            message = Self.noticeText(result.notice)
            // Back on the timer: the page says why the end did not go through.
            if !start, result.mayBeFlowing { pageEvent(.endNotSent(result.notice)) }
            if result.phase == .failed { throw ShowerEngineError.notAllowed }
            if !start, result.phase != .done { throw ShowerEngineError.notAllowed }
        } catch {
            storageBlocked = await engine.storageBlocked
            throw error
        }
    }

    /// Read-only state probe of the session's controller (Settings › 高级 › 检查水控状态).
    func reviewCurrentSession() async {
        guard let engine, let binding, !busy, state.canFinish else { return }
        busy = true; defer { busy = false }
        if let result = try? await engine.review(binding) {
            apply(result)
            message = Self.noticeText(result.notice) ?? (result.phase == .running ? "水控显示正在用水。" : nil)
        }
    }

    /// 再查一次水控 on the needs-check face: the same read-only probe; still running goes back to
    /// the timer (the record says so, nil), otherwise what it found or why it could not look.
    func recheckSession() async -> ShowerRecheckResult? {
        guard let engine, let binding, state.canFinish else { return .unavailable }
        guard !busy else { return .busy }
        busy = true; defer { busy = false }
        do {
            let result = try await engine.review(binding)
            apply(result)
            return ShowerRecheckResult(after:result)
        } catch {
            return ShowerRecheckResult(error:error)
        }
    }

    func resolveManually() async {
        guard let engine, !busy else { return }
        busy = true; defer { busy = false }
        if let result = try? await engine.resolveManually() { apply(result); message = nil }
    }

    func requestSettleRetry() async {
        guard let engine, !busy else { return }
        if let result = try? await engine.requestSettleRetry() { apply(result) }
    }

    func confirmSettleRetry() async {
        guard let engine, let binding, !busy else { return }
        busy = true; defer { busy = false }
        if let result = try? await engine.confirmSettleRetry(binding) { apply(result) }
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
            verifiedDevice = VerifiedShowerDevice(id:id, name:bleName, machineID:binding.machineId.uppercased(), rssi:nil, nearbyCount:nearby, verifiedAt:Date())
            if let proven = outcome.peripheralToRemember { rememberVerified(proven, for:binding) }
            inspectionStatus = Self.inspectionVerifiedText
            inspectionOutcome = .verified
        } catch {
            await bluetooth.disconnect()
            let device = (error as? ShowerDeviceError) ?? .disconnected
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
        guard checked.peripheralID != id, var stored = (try? AppEnvironment.showerVault.binding()) ?? nil,
              stored.machineId == checked.machineId else { return }
        stored.peripheralID = id
        guard (try? AppEnvironment.showerVault.saveBinding(stored)) != nil else { return }
        binding = stored
    }

    private func forgetRemembered(_ id: String, for checked: ShowerBinding) {
        guard var stored = (try? AppEnvironment.showerVault.binding()) ?? nil,
              stored.machineId == checked.machineId, stored.peripheralID == id else { return }
        stored.peripheralID = nil
        guard (try? AppEnvironment.showerVault.saveBinding(stored)) != nil else { return }
        binding = stored
    }

    func exportDiagnostics() throws -> URL {
        try ShowerDiagnosticReport.export(phase:state.phase, needsReview:problem, manualSettleAttempts:state.manualSettleAttempts)
    }

    func show(_ error: Error) { message = AppErrorText.text(error) }

    // MARK: Copy

    static let inspectionVerifiedText = "找到了，是这间的水控。"
    nonisolated static let inspectionShoweringText = "正在洗澡，洗完再核对水控。"
    nonisolated static let inspectionAwaitingCheckText = "上次洗澡还没核对，核对完再来。"
    static let inspectionBusyText = "附近的水控有人在用，现在核对不了是不是这间的。等它空了再试。"

    static func noticeText(_ notice: ShowerNotice?) -> String? {
        switch notice {
        case nil: return nil
        case .device(let e)?: return deviceText(e)
        case .notActive?: return "水控没显示在用水，校日常就没发结束。去学校的热水记录里核对一下这次洗澡。"
        case .wrongDevice?: return "附近的水控不是你宿舍的那台。"
        case .writeUnconfirmed?: return ShowerDisplay.writeUnconfirmedHint
        }
    }

    static func deviceText(_ e: ShowerDeviceError) -> String {
        switch e {
        case .bluetoothOff: return "蓝牙没开，打开后再试。"
        case .notFound: return "附近没找到水控，靠近一点再试。"
        case .ambiguous: return "附近有好几台同名水控，没认出你宿舍的那台。靠近一点再试。"
        case .timedOut: return "水控没回应，靠近一点再试。"
        case .disconnected, .interrupted: return "和水控的连接断了，再试一次。"
        case .malformedFrame: return "水控回的内容看不懂，再试一次。"
        case .busy: return "正在和水控通信，稍等一下。"
        }
    }
}
