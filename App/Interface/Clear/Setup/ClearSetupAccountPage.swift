import SwiftUI
import Core

/// Checklist › 学校账号: the first-run guide's login step (same form, strings and calls) on a
/// pushed page. Signed in, it goes back to the checklist.
struct ClearSetupAccountPage: View {
    /// Back to the checklist.
    let done: () -> Void
    @EnvironmentObject private var campus: CampusModel
    @State private var account: String
    @State private var password: String
    /// 「保存密码，让小组件自动刷新」: on by default only while the account is the saved one.
    @State private var savePassword: Bool
    @State private var loginState: SchoolLoginState
    @State private var webLogin = false
    @State private var issue: String?
    @FocusState private var focus: SchoolLoginField?

    #if DEBUG
    /// DEBUG demo values (`OnboardingDemo`): nothing is sent, the buttons only go back.
    let preview: OnboardingView.Preview?
    init(preview: OnboardingView.Preview? = nil, done: @escaping () -> Void) {
        self.preview = preview; self.done = done
        let typed = preview?.saved?.account ?? preview?.account ?? ""
        _account = State(initialValue:typed)
        _password = State(initialValue:preview?.password ?? "")
        _savePassword = State(initialValue:preview?.saved.map { SchoolAccount.savesPasswordByDefault($0, typed:typed) }
                              ?? preview?.savePassword ?? false)
        _loginState = State(initialValue:preview?.loginState ?? .idle)
    }
    private var previewing: Bool { preview != nil }
    private var savedAccount: SchoolAccount? { previewing ? preview?.saved : campus.account }
    #else
    init(done: @escaping () -> Void) {
        self.done = done
        _account = State(initialValue:""); _password = State(initialValue:"")
        _savePassword = State(initialValue:false); _loginState = State(initialValue:.idle)
    }
    private var previewing: Bool { false }
    private var savedAccount: SchoolAccount? { campus.account }
    #endif

    private var ready: Bool { !account.trimmingCharacters(in:.whitespaces).isEmpty && !password.isEmpty }
    private var loggingIn: Bool { loginState == .loading }

    var body: some View {
        ClearSetupStep(navTitle:SetupChecklist.title(.account), heading:"登录学校账号",
                       message:"用你在学校官网登录时的账号和密码。") {
            SchoolLoginForm(account:$account, password:$password, savePassword:$savePassword,
                            state:loginState, focus:$focus, submit:submit)
            if let issue {
                Label { ClearNoticeText(issue).fixedSize(horizontal:false, vertical:true) } icon: { Image(systemName:"exclamationmark.circle") }
                    .font(.footnote).foregroundStyle(Theme.notice)
            }
        } buttons: {
            if loginState == .cannotDirect {
                ClearSetupButton(title:SchoolLoginText.webLogin, symbol:"arrow.up.right", action:openWebLogin)
            } else {
                ClearSetupButton(title:loggingIn ? "正在登录…" : "登录", busy:loggingIn, action:submit)
                    .disabled(loggingIn || !ready)
                ClearSetupTextButton(title:SchoolLoginText.webLogin, action:openWebLogin)
                    .disabled(loggingIn)
                    .accessibilityIdentifier("webLogin")
            }
        }
        .sheet(isPresented:$webLogin) {
            CampusLoginSheet { value in
                do {
                    try await campus.adoptWebState(value)
                    issue = nil; loginState = .idle; password = ""
                    // The sheet shows 「正在读电量…」 until the card and meter are read.
                    await campus.refresh(force:true)
                    done()
                } catch {
                    issue = error as? SchoolLoginFailure == .busy ? SchoolLoginText.busy : "这次没登录上，再试一次。"
                }
            }
        }
        .onAppear {
            // The saved account is filled in, and its saved password stays saved on a new
            // sign-in unless the box is unticked.
            guard !previewing else { return }
            campus.reloadAccount()
            if account.isEmpty { account = campus.account?.account ?? "" }
            savePassword = SchoolAccount.savesPasswordByDefault(campus.account, typed:account)
        }
        .onChange(of:account) { old, new in
            // Another account typed in: somebody else's password is not kept unless they tick it.
            savePassword = SchoolAccount.savePassword(savePassword, afterEditFrom:old, to:new, saved:savedAccount)
        }
    }

    /// One login with the form's account and password; never retried (failures count towards
    /// the school's lock). Wrong → password cleared and focused; anything the school put in the
    /// way → the primary button becomes the web login.
    private func submit() {
        guard ready, !loggingIn else { return }
        if previewing { done(); return }
        focus = nil
        loginState = .loading
        let name = account, secret = password, save = savePassword
        Task {
            let next = await campus.submitLogin(account:name, password:secret, savePassword:save)
            if next == .idle || next == .wrong { password = "" }
            loginState = next
            if next == .wrong { focus = .password }
            if next == .idle { done() }
        }
    }

    /// The school's own page (behind the loading cover); nothing to save on that path.
    private func openWebLogin() {
        if previewing { done(); return }
        focus = nil
        webLogin = true
    }
}
