import SwiftUI
import CryptoKit
import Core

@MainActor private final class UjingLoginModel: ObservableObject {
    @Published var busy = false
    @Published var issue: String?
    @Published var sent = false
    private func cooldownKey(_ mobile: String) -> String {
        PreferenceKey.prefix + "ujing.smsCooldown." + SHA256.hash(data:Data(mobile.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    func remaining(_ mobile: String, at date: Date = Date()) -> Int {
        max(0,Int(ceil(UserDefaults.standard.double(forKey:cooldownKey(mobile)) - date.timeIntervalSince1970)))
    }
    func send(_ mobile: String, laundry: LaundryModel) async {
        guard !busy, UjingInput.isMobile(mobile), remaining(mobile) == 0 else { return }
        // Reserve the cooldown before sending, including uncertain network outcomes. No automatic retry.
        UserDefaults.standard.set(Date().addingTimeInterval(60).timeIntervalSince1970,forKey:cooldownKey(mobile))
        busy = true; issue = nil; sent = false; defer { busy = false }
        do { try await laundry.requestSMS(mobile:mobile); sent = true }
        catch { issue = (error as? ServiceError)?.userMessage ?? "验证码可能没发出去，过一会儿再试。" }
    }
    func login(_ mobile: String, code: String, laundry: LaundryModel) async -> Bool {
        guard !busy else { return false }
        busy = true; issue = nil; defer { busy = false }
        do {
            try await laundry.login(mobile:mobile, code:code)
            return true
        } catch { issue = (error as? ServiceError)?.userMessage ?? "登录没完成，核对手机号和验证码再试。"; return false }
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
                    TextField("U净 绑定手机号",text:$mobile).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .accessibilityIdentifier("ujingMobile")
                    HStack {
                        TextField("短信验证码",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .accessibilityIdentifier("ujingSMSCode")
                        TimelineView(.periodic(from:Date(),by:1)) { timeline in
                            let remaining = login.remaining(mobile,at:timeline.date)
                            Button(remaining > 0 ? "\(remaining)秒后重试" : "获取验证码") { Task { await login.send(mobile, laundry:laundry) } }
                                .disabled(login.busy || !consent || !UjingInput.isMobile(mobile) || remaining > 0)
                                .accessibilityIdentifier("sendUjingSMS")
                        }
                    }
                    Toggle("我已阅读并同意 U净 服务协议和隐私政策",isOn:$consent).font(.footnote)
                    HStack(spacing:20) {
                        Link("服务协议",destination:URL(string:"https://wx.zhinengxiyifang.cn/about_us/service_agreement.html")!)
                        Link("隐私政策",destination:URL(string:"https://wx.zhinengxiyifang.cn/static/user-agreement/app2.0/20260804/ujing_privacy_policy.html")!)
                    }.font(.footnote)
                } footer: { Text("用你自己的 U净 账号。手机号和验证码只发给 U净 官方，登录信息只存在这台手机上。") }
                if login.sent { Text("验证码已发出，看一下短信。").font(.footnote).foregroundStyle(.secondary) }
                if let issue = login.issue { Text(issue).font(.footnote).foregroundStyle(.orange) }
                Button {
                    Task { if await login.login(mobile,code:code,laundry:laundry) { code = ""; dismiss() } }
                } label: { HStack { if login.busy { ProgressView() }; Text("登录 U净") }.frame(maxWidth:.infinity) }
                    .disabled(login.busy || !consent || !UjingInput.isMobile(mobile) || code.count < 4 || !laundry.mayImport)
                    .accessibilityIdentifier("confirmUjingLogin")
            }.navigationTitle("登录 U净").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() }.disabled(login.busy) } }
                .interactiveDismissDisabled(login.busy)
                .onDisappear { code = ""; mobile = "" }
        }
    }
}
