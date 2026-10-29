import Foundation
import Combine
import WaterCore

@MainActor final class WaterModel: ObservableObject {
    static let shared = WaterModel()
    @Published private(set) var configured = false
    @Published private(set) var busy = false
    @Published private(set) var stage: SessionStage?
    @Published private(set) var status = "导入个人配置后即可使用"
    @Published private(set) var problem = false
    @Published private(set) var lastEnded: Date?
    @Published private(set) var lastCost: Decimal?
    @Published private(set) var hasReceipt = false
    private var controller: WaterController?
    private var config: WaterConfig?
    @Published private var importedPlatform: WaterPlatformProfile?
    @Published private var reviewingIdentity = false
    @Published private(set) var residenceReviewRequired = UserDefaults.standard.bool(forKey:"water.needsResidenceReview")
    @Published private(set) var verifiedDevice: VerifiedWaterDevice?
    @Published private(set) var inspectionStatus: String?
    @Published private(set) var inspecting = false
    @Published private(set) var deviceCandidates: [WaterDeviceCandidate] = []
    private var deviceChoice: CheckedContinuation<String, Error>?
    private var selectionAllowed = false
    private let bluetooth = BluetoothTransport()
    private init() {
        bluetooth.targetPicker = { [weak self] candidates in
            guard let self, self.selectionAllowed else { throw WaterError.targetAmbiguous }
            return try await self.requestDevice(candidates)
        }
        do {
            controller = try WaterController(transport: bluetooth, provider: HTTPSWaterProvider(), store: FileSessionStore(), diagnostics: WaterDiagnosticReport.trace)
            config = try PrivateConfigStore.load()
            importedPlatform = try WaterPlatformStore.load()
            configured = config != nil
            refresh()
        } catch { status = WaterError.storage.rawValue; problem = true }
    }
    var mayStart: Bool { configured && !reviewingIdentity && !residenceReviewRequired && config?.access == nil && controller != nil && !busy && (stage == nil || stage == .settled) && controller?.storageBlocked == false }
    var mayFinish: Bool { configured && !busy && stage?.mayClose == true && controller?.storageBlocked == false }
    var mayImport: Bool { controller != nil && !busy && (stage == nil || stage == .settled) && controller?.storageBlocked == false }
    var onboardingSeed: WaterConfig? { config }
    var onboardingProfile: WaterPlatformProfile? {
        if let config, config.access == nil { return WaterPlatformProfile(legacy:config) }
        if let importedPlatform, importedPlatform.access == nil {return importedPlatform}
        return bundledPlatform
    }
    private var bundledPlatform: WaterPlatformProfile? {
        guard let url = Bundle.main.url(forResource:"CampusWaterPlatform",withExtension:"json"),
              let bytes = try? Data(contentsOf:url) else { return nil }
        return try? WaterPlatformProfile.parseImport(bytes)
    }
    func migrateBundledDirectIfNeeded(campus: CampusConfig?) async {
        guard let old = config, old.access != nil, let campus, mayImport else {return}
        guard let profile = bundledPlatform else {status = OnboardingError.platform.rawValue;problem = true;return}
        busy = true
        defer {busy = false}
        do {
            let who = try await DormOnboardingProvider().identity(campus:campus,seed:profile)
            guard config == old else {throw WaterError.interrupted}
            let next = try profile.migrateToDirect(old,owner:campus.waterAccessOwner,student:who.student,
                school:who.school,unresolved:controller?.session.map{$0.stage != .settled} ?? false)
            try PrivateConfigStore.save(next);config = next;configured = true;problem = false;refresh()
        } catch {show(error)}
    }
    func importPlatform(_ url: URL) throws {
        guard mayImport, !configured else {throw WaterError.unresolved}
        let access = url.startAccessingSecurityScopedResource()
        defer {if access {url.stopAccessingSecurityScopedResource()}}
        guard let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 8192 else {throw WaterError.invalidConfig}
        let value = try WaterPlatformProfile.parseImport(Data(contentsOf:url))
        try WaterPlatformStore.save(value)
        importedPlatform = value
    }
    func acceptDorm(_ value: WaterConfig) throws {
        guard mayImport else { throw WaterError.unresolved }
        try value.validate(); try PrivateConfigStore.save(value)
        config = value; configured = true; reviewingIdentity = false; residenceReviewRequired = false
        UserDefaults.standard.set(false,forKey:"water.needsResidenceReview")
        problem = false; refresh()
    }
    func requireResidenceReview() {
        guard configured else {return}
        residenceReviewRequired = true
        UserDefaults.standard.set(true,forKey:"water.needsResidenceReview")
        refresh()
    }
    /// Roll back an interrupted two-part dorm save, including first setup.
    func restoreDorm(_ previous: WaterConfig?, reviewRequired: Bool) throws {
        do {
            guard mayImport else {throw WaterError.unresolved}
            if let previous {
                try previous.validate();try PrivateConfigStore.save(previous)
                config = previous;configured = true
            } else {
                try PrivateConfigStore.clear();config = nil;configured = false
            }
            reviewingIdentity = false;residenceReviewRequired = reviewRequired
            UserDefaults.standard.set(reviewRequired,forKey:"water.needsResidenceReview")
            problem = false;refresh()
        } catch {
            // A failed rollback must not make the partial configuration usable.
            reviewingIdentity = true;residenceReviewRequired = true
            UserDefaults.standard.set(true,forKey:"water.needsResidenceReview")
            problem = true
            status = "宿舍保存未完成，请重新核对校园账号和水控"
            throw error
        }
    }
    func acceptAccess(_ access: WaterAccessSession) throws {
        guard mayImport else {throw WaterError.unresolved}
        try access.validate()
        let profile = WaterPlatformProfile(access:access)
        try WaterPlatformStore.save(profile)
        if let old = config, old.access != nil {
            if old.studentID == access.studentID && old.schoolID == access.schoolID {
                let next = try profile.configuration(student:old.studentID,school:old.schoolID,machine:old.machineID)
                try PrivateConfigStore.save(next);config = next
            } else {
                try PrivateConfigStore.clear();config = nil;configured = false
            }
        }
        importedPlatform = profile
    }
    func scopeAccess(to campus: CampusConfig) throws {
        guard mayImport else {throw WaterError.unresolved}
        reviewingIdentity = true
        if let access = config?.access, access.campusOwner != campus.waterAccessOwner {
            try PrivateConfigStore.clear();config = nil;configured = false
        }
        if let access = importedPlatform?.access, access.campusOwner != campus.waterAccessOwner {importedPlatform = nil}
    }
    func confirmDirectIdentity(student: String,school: String,profile: WaterPlatformProfile) throws {
        guard mayImport, profile.access == nil else {throw WaterError.unresolved}
        if let old = config, old.studentID != student || old.schoolID != school {
            try WaterPlatformStore.save(profile); importedPlatform = profile
            try PrivateConfigStore.clear();config = nil;configured = false
        }
        reviewingIdentity = false
    }
    private func refresh() {
        stage = controller?.session?.stage
        lastEnded = controller?.session?.endedAt
        lastCost = controller?.session?.receipt?.amountYuan
        hasReceipt = controller?.session?.receipt != nil
        if controller?.session?.requiresStateReview == true {
            problem = true
            status = WaterError.notActive.rawValue + "；请核对现场及官方用水记录"
        } else if residenceReviewRequired && (stage == nil || stage == .settled) {
            status = "学校宿舍已变更，请先重新确认宿舍水控";problem = true
        } else if let stage { status = stage.label }
        else if configured { status = config?.access?.isCurrent == false ? "请重新登录学校账号以更新热水连接" : "准备好了，靠近水控即可开始" }
    }
    func importConfig(_ url: URL) throws {
        guard mayImport else { throw WaterError.unresolved }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 16384 else { throw WaterError.invalidConfig }
        let value: WaterConfig
        do { value = try JSONDecoder().decode(WaterConfig.self, from: data); try value.validate() }
        catch { throw WaterError.invalidConfig }
        try PrivateConfigStore.save(value)
        config = value; configured = true; problem = false
        refresh()
    }
    // Xcode development provisioning: one private file copied into this app's sandbox.
    // Personal identities remain outside the bundle; the shared platform is a build resource.
    func importDevelopmentConfigIfPresent() {
        guard mayImport else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bootstrap.waterconfig")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try importConfig(url); try FileManager.default.removeItem(at: url) }
        catch { show(error) }
    }
    func show(_ error: Error) {
        refresh()
        problem = true
        status = (error as? LocalizedError)?.errorDescription ?? "操作未确认，请查看当前记录后再继续"
        WaterDiagnosticReport.trace.record(.operationFailed, stage: stage, error: (error as? WaterError) ?? .interrupted)
        if (error as? WaterError) == .wrongDevice, mayImport {
            status = "所选水控不属于已保存的宿舍，请在连接检查中重新选择设备"
        }
    }
    private func requestDevice(_ candidates: [WaterDeviceCandidate]) async throws -> String {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                deviceChoice = continuation
                deviceCandidates = candidates
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancelDeviceSelection() } })
    }
    func chooseDevice(_ id: String) {
        guard deviceCandidates.contains(where: { $0.id == id }) else { return }
        let choice = deviceChoice
        deviceChoice = nil; deviceCandidates = []
        choice?.resume(returning:id)
    }
    func cancelDeviceSelection() {
        selectionAllowed = false
        let choice = deviceChoice
        deviceChoice = nil; deviceCandidates = []
        choice?.resume(throwing:WaterError.interrupted)
    }
    private func deviceKey(_ config: WaterConfig) -> String { "water.verifiedPeripheral." + config.machineID.uppercased() }
    func exportDiagnostics() throws -> URL {
        try WaterDiagnosticReport.export(stage: stage, needsReview: controller?.session?.requiresStateReview == true)
    }
    func reviewCurrentSession() async {
        guard mayFinish, let controller, let config else { return }
        busy = true; status = "正在只读检查水控状态…"
        defer { busy = false }
        do {
            _ = try await controller.review(config: config)
            problem = false; refresh()
        } catch { show(error) }
    }
    func inspectBluetooth() async {
        guard mayImport, let config, let controller else { return }
        busy = true; inspecting = true; selectionAllowed = true; verifiedDevice = nil
        inspectionStatus = "正在扫描并核对宿舍设备…"
        defer { busy = false; inspecting = false; selectionAllowed = false }
        do {
            let id = try await controller.identify(config:config)
            UserDefaults.standard.set(id,forKey:deviceKey(config))
            verifiedDevice = bluetooth.verifiedInformation(id:id,machineID:config.machineID)
            inspectionStatus = "已匹配本宿舍水控，设备已保存"
        } catch {
            inspectionStatus = (error as? LocalizedError)?.errorDescription ?? "暂未确认水控，请靠近设备后重试"
        }
    }
    func run(start: Bool, allowDeviceSelection: Bool = false) async throws {
        guard !busy else { throw WaterError.busy }
        guard !start || (!reviewingIdentity && !residenceReviewRequired) else {throw OnboardingError.identity}
        guard let controller, let config else { throw WaterError.invalidConfig }
        guard config.access == nil else {throw OnboardingError.identity}
        busy = true; problem = false; selectionAllowed = allowDeviceSelection
        status = start ? "正在连接并申请授权…" : "正在结束并结算…"
        defer { busy = false; selectionAllowed = false }
        do {
            if start {
                try await controller.start(config:config,preferredPeripheral:UserDefaults.standard.string(forKey:deviceKey(config)))
                if let id = controller.session?.peripheralID { UserDefaults.standard.set(id,forKey:deviceKey(config)) }
            }
            else { try await controller.finish(config: config) }
            refresh()
        } catch {
            if (error as? WaterError) == .wrongDevice, start {
                UserDefaults.standard.removeObject(forKey:deviceKey(config))
            }
            show(error)
            throw (error as? WaterError) ?? WaterError.interrupted
        }
    }
}
