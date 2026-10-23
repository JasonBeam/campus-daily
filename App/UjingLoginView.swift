import SwiftUI
import Security
import CryptoKit
import WaterCore

struct UjingConnection: Codable {
    var account: UjingAccount
    var selected: SavedWasher?
    var config: LaundryConfig? {
        selected.map { LaundryConfig(headers:account.headers,qrCode:$0.qrCode,deviceId:$0.id,accountID:account.id) }
    }
}

enum UjingConnectionStore {
    private static var key: [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"CampusHotWater.ujing-account.v1",kSecAttrAccount as String:"connection"]
    }
    static func load() throws -> UjingConnection? {
        var query = key; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 32768 else { throw WaterError.storage }
        let value = try JSONDecoder().decode(UjingConnection.self,from:data)
        try value.account.validate(); try value.config?.validate(); return value
    }
    static func save(_ value: UjingConnection) throws {
        try value.account.validate(); try value.config?.validate()
        let changes: [String:Any] = [kSecValueData as String:try JSONEncoder().encode(value),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(key as CFDictionary,changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = key; changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw WaterError.storage }
        } else if status != errSecSuccess { throw WaterError.storage }
    }
    static func clear() throws {
        let status = SecItemDelete(key as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WaterError.storage }
    }
}

@MainActor private final class UjingLoginModel: ObservableObject {
    @Published var busy = false
    @Published var issue: String?
    @Published var sent = false
    private let provider: UjingLoginProvider
    init() {
        let key = "ujingClientInstallationID"
        let client = UserDefaults.standard.string(forKey:key) ?? UUID().uuidString
        UserDefaults.standard.set(client,forKey:key)
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "dev"
        provider = UjingLoginProvider(clientID:client,userAgent:"XiaoRiChang/\(version) (iPhone; iOS \(UIDevice.current.systemVersion))")
    }
    private func cooldownKey(_ mobile: String) -> String {
        "ujingSMSCooldown." + SHA256.hash(data:Data(mobile.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    func remaining(_ mobile: String, at date: Date = Date()) -> Int {
        max(0,Int(ceil(UserDefaults.standard.double(forKey:cooldownKey(mobile)) - date.timeIntervalSince1970)))
    }
    func send(_ mobile: String) async {
        guard !busy, UjingLoginProvider.validMobile(mobile), remaining(mobile) == 0 else { return }
        // Reserve the cooldown before sending, including uncertain network outcomes. No automatic retry.
        UserDefaults.standard.set(Date().addingTimeInterval(60).timeIntervalSince1970,forKey:cooldownKey(mobile))
        busy = true; issue = nil; sent = false; defer { busy = false }
        do { try await provider.sendCode(mobile:mobile); sent = true }
        catch { issue = (error as? LocalizedError)?.errorDescription ?? "验证码请求未确认，请稍后再试" }
    }
    func login(_ mobile: String, code: String, laundry: LaundryModel) async -> Bool {
        guard !busy else { return false }
        busy = true; issue = nil; defer { busy = false }
        do {
            let account = try await provider.login(mobile:mobile,captcha:code)
            try laundry.connect(account)
            return true
        } catch { issue = (error as? LocalizedError)?.errorDescription ?? "登录未完成，请核对信息后重试"; return false }
    }
}

struct UjingLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var laundry: LaundryModel
    @StateObject private var login = UjingLoginModel()
    @State private var mobile = ""
    @State private var code = ""
    @State private var consent = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("U净绑定手机号",text:$mobile).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .accessibilityIdentifier("ujingMobile")
                    HStack {
                        TextField("短信验证码",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .accessibilityIdentifier("ujingSMSCode")
                        TimelineView(.periodic(from:Date(),by:1)) { timeline in
                            let remaining = login.remaining(mobile,at:timeline.date)
                            Button(remaining > 0 ? "\(remaining)秒后重试" : "获取验证码") { Task { await login.send(mobile) } }
                                .disabled(login.busy || !consent || !UjingLoginProvider.validMobile(mobile) || remaining > 0)
                                .accessibilityIdentifier("sendUjingSMS")
                        }
                    }
                    Toggle("我已阅读并同意 U净服务协议和隐私政策",isOn:$consent).font(.footnote)
                    HStack(spacing:20) {
                        Link("服务协议",destination:URL(string:"https://wx.zhinengxiyifang.cn/about_us/service_agreement.html")!)
                        Link("隐私政策",destination:URL(string:"https://wx.zhinengxiyifang.cn/static/user-agreement/app2.0/20260804/ujing_privacy_policy.html")!)
                    }.font(.footnote)
                } footer: { Text("使用你自己的 U净账号。手机号与验证码仅发送给 U净官方登录接口，登录凭据保存在本机钥匙串。") }
                if login.sent { Text("已请求验证码，请查看短信").font(.footnote).foregroundStyle(.secondary) }
                if let issue = login.issue { Text(issue).font(.footnote).foregroundStyle(.orange) }
                Button {
                    Task { if await login.login(mobile,code:code,laundry:laundry) { code = ""; dismiss() } }
                } label: { HStack { if login.busy { ProgressView() }; Text("登录 U净") }.frame(maxWidth:.infinity) }
                    .disabled(login.busy || !consent || !UjingLoginProvider.validMobile(mobile) || code.count < 4 || !laundry.mayImport)
                    .accessibilityIdentifier("confirmUjingLogin")
            }.navigationTitle("登录 U净").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() }.disabled(login.busy) } }
                .interactiveDismissDisabled(login.busy)
                .onDisappear { code = ""; mobile = "" }
        }
    }
}
