import AppIntents
import Core

/// The intents run on the live session (`ShowerModel.shared`), never on a sample's. While
/// 「先看看示例」 is on (`sample`, set by the app) the app opens on the sample, where the live
/// session is not shown: no shower is started from there. 结束并结算 leaves the sample first, then
/// ends the live one (water may be running), as the Live Activity's button does (`LiveShowerFinish`).
enum ShowerIntentGate {
    @MainActor static weak var sample: SampleMode?
    @MainActor static var sampleActive: Bool { sample?.isActive ?? false }
    static let sampleText = "先点「去登录」退出示例，再开始洗澡。"
}

struct StartShowerIntent: AppIntent {
    static let title: LocalizedStringResource = "开始洗澡"
    static let description = IntentDescription("连接你的水控并申请本次授权，然后按水控上的出水键。")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppEnvironment.live.debugNav.from(.intent)
        guard !ShowerIntentGate.sampleActive else { throw ShowerActionFailure(ShowerIntentGate.sampleText) }
        // Throws `ShowerActionFailure`: the system shows its real reason.
        switch try await ShowerModel.shared.run(start: true) {
        case .startUnconfirmed: return .result(dialog: "\(ShowerActionOutcome.startUnconfirmedText)")
        default: return .result(dialog: "\(ShowerActionOutcome.startedText)")
        }
    }
}

struct FinishShowerIntent: AppIntent {
    static let title: LocalizedStringResource = "结束并结算"
    static let description = IntentDescription("结束本 App 开启的热水会话并提交结算。")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppEnvironment.live.debugNav.from(.intent)
        // Throws the real reason (`ShowerActionFailure`). Shown over the sample: it is left first.
        _ = try await LiveShowerFinish.run(sample: ShowerIntentGate.sample) { try await ShowerModel.shared.run(start: false) }
        if let amount = ShowerModel.shared.lastCost {
            let text = amount.formatted(.currency(code:"CNY").locale(Locale(identifier:"zh_CN")))
            return .result(dialog: "已结算，这次\(text)。看一眼水停了没。")
        }
        return .result(dialog: "已结算。看一眼水停了没。")
    }
}

struct ShowerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartShowerIntent(), phrases: ["用\(.applicationName)开始洗澡"],
                    shortTitle: "开始洗澡", systemImageName: "drop.fill")
        AppShortcut(intent: FinishShowerIntent(), phrases: ["用\(.applicationName)结束并结算"],
                    shortTitle: "结束并结算", systemImageName: "stop.circle")
    }
}
