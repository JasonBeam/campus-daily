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
    private let bluetooth = BluetoothTransport()
    private init() {
        do {
            controller = try WaterController(transport: bluetooth, provider: HTTPSWaterProvider(), store: FileSessionStore())
            config = try PrivateConfigStore.load()
            configured = config != nil
            refresh()
        } catch { status = WaterError.storage.rawValue; problem = true }
    }
    var mayStart: Bool { configured && controller != nil && !busy && (stage == nil || stage == .settled) && controller?.storageBlocked == false }
    var mayFinish: Bool { configured && !busy && stage?.mayClose == true && controller?.storageBlocked == false }
    var mayImport: Bool { controller != nil && !busy && (stage == nil || stage == .settled) && controller?.storageBlocked == false }
    var onboardingSeed: WaterConfig? { config }
    var onboardingProfile: WaterPlatformProfile? {
        if let config { return WaterPlatformProfile(legacy:config) }
        guard let url = Bundle.main.url(forResource:"WaterPlatformProfile",withExtension:"json"),
              let bytes = try? Data(contentsOf:url), bytes.count <= 4096 else { return nil }
        return try? JSONDecoder().decode(WaterPlatformProfile.self,from:bytes)
    }
    func acceptDorm(_ value: WaterConfig) throws {
        guard mayImport else { throw WaterError.unresolved }
        try value.validate(); try PrivateConfigStore.save(value)
        config = value; configured = true; problem = false; refresh()
    }
    private func refresh() {
        stage = controller?.session?.stage
        lastEnded = controller?.session?.endedAt
        lastCost = controller?.session?.receipt?.amountYuan
        hasReceipt = controller?.session?.receipt != nil
        if let stage { status = stage.label }
        else if configured { status = "准备好了，靠近水控即可开始" }
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
    // A normal release contains no bundled identity or signing secret.
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
        status = (error as? WaterError)?.rawValue ?? "操作未确认，请查看当前记录后再继续"
    }
    func inspectBluetooth() async {
        guard !busy, let config else { return }
        busy = true; status = "正在检查附近水控…"
        defer { busy = false }
        let remembered = controller?.session?.machineID == config.machineID.uppercased() ? controller?.session?.peripheralID : nil
        do { status = try await bluetooth.inspect(config:config,remembered:remembered) }
        catch { show(error) }
    }
    func run(start: Bool) async throws {
        guard !busy else { throw WaterError.busy }
        guard let controller, let config else { throw WaterError.invalidConfig }
        busy = true; problem = false
        status = start ? "正在连接并申请授权…" : "正在结束并结算…"
        defer { busy = false }
        do {
            if start { try await controller.start(config: config) }
            else { try await controller.finish(config: config) }
            refresh()
        } catch {
            show(error)
            throw (error as? WaterError) ?? WaterError.interrupted
        }
    }
}
