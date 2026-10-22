import AppIntents

struct StartShowerIntent: AppIntent {
    static var title: LocalizedStringResource = "开始洗澡"
    static var description = IntentDescription("连接你的水控并申请本次授权，随后请按设备出水键。")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await WaterModel.shared.run(start: true)
        return .result(dialog: "已取得水控确认，请按设备出水键。")
    }
}

struct FinishShowerIntent: AppIntent {
    static var title: LocalizedStringResource = "结束结算"
    static var description = IntentDescription("结束本 App 开启的热水会话并提交结算。")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        try await WaterModel.shared.run(start: false)
        if let amount = WaterModel.shared.lastCost {
            let text = amount.formatted(.currency(code:"CNY").locale(Locale(identifier:"zh_CN")))
            return .result(dialog: "已结算，本次费用 \(text)。请确认现场已停水。")
        }
        return .result(dialog: "服务器已确认结算，请确认现场已停水。")
    }
}

struct WaterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartShowerIntent(), phrases: ["用\(.applicationName)开始洗澡"],
                    shortTitle: "开始洗澡", systemImageName: "drop.fill")
        AppShortcut(intent: FinishShowerIntent(), phrases: ["用\(.applicationName)结束结算"],
                    shortTitle: "结束结算", systemImageName: "stop.circle")
    }
}
