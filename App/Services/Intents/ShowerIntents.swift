import AppIntents

struct StartShowerIntent: AppIntent {
    static let title: LocalizedStringResource = "开始洗澡"
    static let description = IntentDescription("连接你的水控并申请本次授权，然后按水控上的出水键。")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ShowerModel.shared.run(start: true)
        return .result(dialog: "水控连上了，按出水键开水。")
    }
}

struct FinishShowerIntent: AppIntent {
    static let title: LocalizedStringResource = "结束并结算"
    static let description = IntentDescription("结束本 App 开启的热水会话并提交结算。")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ShowerModel.shared.run(start: false)
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
