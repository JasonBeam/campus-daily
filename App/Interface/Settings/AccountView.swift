import SwiftUI
import Core

/// Copy for 学校账号, including the paused automatic sign-in.
enum AccountText {
    static let signedIn = "已登录"
    static let paused = "自动登录已暂停"
    static let reenter = "重新输入密码"
    static let reenterTitle = "输入学校密码"
    static let keychainNote = "密码只存在这台 iPhone 的钥匙串里。"
    static let wrongPassword = "密码不对，没保存。"
    static let savedFooter = "小组件会自动刷新。关掉会删掉存着的密码。"
    static let notSavedFooter = "不保存的话，过几个小时小组件就要打开 App 才能更新。"
    static let pausedRefused = "存的密码登录不上，自动登录先停了。可能是在学校那边改过密码，重新输入就能恢复。"
    static let signOutFailed = "退出没完成，再试一次。"
    static let pausedNoAnswer = "上次登录学校没回应，为免账号被锁，自动登录先停几个小时，到时会自己恢复。"

    /// The 学校账号 row on the settings page.
    static func row(signedIn: Bool, account: SchoolAccount?, at now: Date = Date()) -> String {
        guard signedIn else { return "去登录" }
        return account?.autoLogin(at:now).isPaused == true ? paused : AccountText.signedIn
    }

    static func footer(_ state: SchoolAccount.AutoLogin) -> String {
        switch state {
        case .off: return notSavedFooter
        case .on: return savedFooter
        case .pausedRefused: return pausedRefused
        case .pausedNoAnswer: return pausedNoAnswer
        }
    }
}

/// 学校账号 detail: account, status, 保存密码 (and 重新输入密码 while paused),
/// re-login, sign out.
struct AccountView: View {
    var preview: HomeData? = nil
    @EnvironmentObject private var campus: CampusModel
    @State private var confirmSignOut = false
    @State private var askPassword = false
    @State private var typedAccount = ""
    @State private var typedPassword = ""
    /// The last save was not sent (or got no answer): the next alert opens with what was typed.
    @State private var keepTyped = false
    @State private var saving = false
    @State private var saveIssue: String?
    /// The typed account isn't the signed-in one: nothing saved, nobody switched.
    /// Why 保存密码 was refused (another account, or the stored login can't be read).
    @State private var refusal: SchoolLoginFailure.SavePasswordRefusal?
    /// 重新输入密码 (only while automatic sign-in is paused).
    @State private var askReenter = false
    /// 重新登录学校账号: the account-and-password sheet.
    @State private var relogin = false
    /// DEBUG demo: the switch flips locally (seeded from the demo data).
    @State private var previewSaved: Bool?
    private var signedIn: Bool { preview?.signedIn ?? campus.configured }
    private var dorm: String? { preview?.dorm ?? Theme.dorm(campus.room) }
    private var account: SchoolAccount? { preview != nil ? preview?.schoolAccount : campus.account }
    private var passwordSaved: Bool { preview != nil ? (previewSaved ?? preview?.passwordSaved ?? false) : campus.passwordSaved }
    /// Off / on / paused (refused or no answer). Re-read on every redraw, so a hold that ran
    /// out shows as on the next time the page draws.
    private var autoLogin: SchoolAccount.AutoLogin {
        if preview != nil, previewSaved == false { return .off }
        if preview != nil, previewSaved == true, account?.password == nil { return .on }
        return account?.autoLogin(at:Date()) ?? .off
    }
    private var paused: Bool { autoLogin.isPaused }
    private var passwordSwitch: Binding<Bool> {
        Binding(get:{ passwordSaved || askPassword || saving }, set:{ on in
            saveIssue = nil
            if on {
                if !keepTyped { typedAccount = ""; typedPassword = "" }
                keepTyped = false
                askPassword = true
            } else if preview != nil {
                previewSaved = false
            } else {
                Task {
                    // Not stored as asked (the Keychain refused, or an update held the lease):
                    // the switch shows what is stored, and this says why.
                    do { try await campus.forgetPassword() } catch { saveIssue = SchoolLoginText.text(error) }
                }
            }
        })
    }

    var body: some View {
        List {
            Section {
                if let account { LabeledContent("账号") { Text(account.masked).monospacedDigit() } }
                if signedIn && paused {
                    // Not red: red only means something is running out.
                    LabeledContent("状态") {
                        Text(AccountText.paused).scaledFont(16, .medium).foregroundStyle(Theme.accentText)
                    }
                    .accessibilityIdentifier("accountStatusPaused")
                } else {
                    LabeledContent("状态", value:signedIn ? AccountText.signedIn : "未登录")
                }
                if signedIn, let dorm { LabeledContent("宿舍", value:dorm) }
            }.listRowBackground(Theme.group)
            if signedIn {
                Section {
                    Toggle(isOn:passwordSwitch) {
                        HStack(spacing:8) {
                            Text("保存密码").foregroundStyle(Theme.ink)
                            if saving { ProgressView() }
                        }
                    }
                    .tint(.green)
                    .disabled(saving)
                    .accessibilityIdentifier("savePasswordSwitch")
                    if paused {
                        Button {
                            saveIssue = nil; if !keepTyped { typedPassword = "" }; keepTyped = false; askReenter = true
                        } label: {
                            Text(AccountText.reenter).scaledFont(16, .medium).foregroundStyle(Theme.accentText)
                                .frame(maxWidth:.infinity, alignment:.leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(saving)
                        .accessibilityIdentifier("reenterPassword")
                    }
                } footer: {
                    VStack(alignment:.leading, spacing:6) {
                        if let saveIssue {
                            Label(saveIssue, systemImage:"exclamationmark.circle.fill").foregroundStyle(Theme.accentText)
                                .accessibilityIdentifier("savePasswordIssue")
                        }
                        Text(AccountText.footer(autoLogin))
                            .foregroundStyle(Theme.ink2)
                    }
                }.listRowBackground(Theme.group)
            }
            Section {
                // Account and password first, the school's web page as the fallback.
                Button { relogin = true } label: {
                    ChevronRow(title:signedIn ? "重新登录学校账号" : "登录学校账号")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("relogin")
            } footer: {
                Text("密码只交给学校，不经过我们。").foregroundStyle(Theme.ink2)
            }.listRowBackground(Theme.group)
            if signedIn {
                Section {
                    Button("退出登录", role:.destructive) { confirmSignOut = true }
                        .frame(maxWidth:.infinity)
                        // Only while a password check is in flight. A running refresh is no reason:
                        // sign-out drops it (its late result is never written back).
                        .disabled(saving)
                }.listRowBackground(Theme.group)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("学校账号").navigationBarTitleDisplayMode(.inline)
        .background {
            // The system tint: on iOS 27 an alert fills its main button with the default blue,
            // and accent-coloured text on it can't be read.
            Color.clear
                .alert(account == nil ? "输入学校账号和密码" : "输入学校账号的密码", isPresented:$askPassword) {
                    // Signed in on the web page: the account was never told to us, so ask for it too.
                    if account == nil {
                        TextField("账号", text:$typedAccount)
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    SecureField("密码", text:$typedPassword).textContentType(.password)
                    Button("取消", role:.cancel) { typedPassword = ""; keepTyped = false }
                    Button("保存") { save() }
                } message: {
                    Text("密码只存在这台 iPhone 的钥匙串里。")
                }
                .alert(AccountText.reenterTitle, isPresented:$askReenter) {
                    SecureField("密码", text:$typedPassword).textContentType(.password)
                    Button("取消", role:.cancel) { typedPassword = ""; keepTyped = false }
                    Button("保存") { save() }
                } message: {
                    Text(AccountText.keychainNote + "\n账号 " + (account?.masked ?? ""))
                }
                .alert(AccountText.signOutFailed, isPresented:$campus.signOutFailed) {
                    Button("好", role:.cancel) {}
                }
                .alert(refusal?.title ?? "", isPresented:Binding(get:{ refusal != nil }, set:{ if !$0 { refusal = nil } })) {
                    Button("好", role:.cancel) {}
                } message: {
                    Text(refusal?.message ?? "")
                }
                .tint(nil)
        }
        .sheet(isPresented:$relogin) { SchoolReloginSheet(preview:preview.map { _ in account ?? SchoolAccount(account:"") }) }
        // A pause written by a refresh (foreground, background or the widget) shows on arrival.
        .onAppear { if preview == nil { campus.reloadAccount() } }
        .confirmationDialog("退出学校账号？", isPresented:$confirmSignOut, titleVisibility:.visible) {
            // DEBUG demo data: the dialog shows, nothing is signed out.
            Button("退出登录", role:.destructive) { if preview == nil { campus.signOut() } }
            Button("取消", role:.cancel) {}
        } message: {
            Text("首页的电量和余额会清空，热水记录和洗衣设置都还在。")
        }
    }

    /// One login checks the password before it is kept; never retried.
    private func save() {
        let password = typedPassword, name = typedAccount.trimmingCharacters(in:.whitespaces)
        let askedAccount = account == nil
        typedPassword = ""
        guard !password.isEmpty else { return }
        if preview != nil {
            // DEBUG demo of the web-login case: any account but the demo one is someone else.
            if askedAccount, !name.isEmpty, name != "99100991" { refusal = SchoolLoginFailure.differentAccount.savePasswordRefusal } else { previewSaved = true }
            return
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await campus.savePassword(password, account:account == nil ? name : nil)
            } catch SchoolLoginFailure.wrongCredentials {
                saveIssue = askedAccount ? "账号或密码不对，没保存。" : AccountText.wrongPassword
            } catch let failure as SchoolLoginFailure where failure.savePasswordRefusal != nil {
                refusal = failure.savePasswordRefusal
            } catch {
                saveIssue = SchoolLoginText.text(error)
                // Not sent (正在更新) or no answer: what was typed is there for the next try.
                if (error as? SchoolLoginFailure)?.keepsTypedPassword == true {
                    typedPassword = password; typedAccount = name; keepTyped = true
                }
            }
        }
    }
}
