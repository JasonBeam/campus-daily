import SwiftUI
import Core

/// 「重新登录学校账号」 from Settings and the top-up page: the first-run login
/// form in a full-height sheet, account and password first, the school's web page as the
/// fallback. No mascot, no page dots.
struct SchoolReloginSheet: View {
    @EnvironmentObject private var campus: CampusModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// After a successful sign-in (form or web), before the sheet closes.
    var signedIn: () async -> Void = {}
    /// DEBUG demo: seed from this account; nothing is sent.
    var preview: SchoolAccount? = nil
    @State private var account = ""
    @State private var password = ""
    @State private var savePassword = false
    @State private var state = SchoolLoginState.idle
    @State private var webLogin = false
    @State private var seeded = false
    @FocusState private var focus: SchoolLoginField?

    private var keyboardUp: Bool { focus != nil }
    private var ready: Bool { !account.trimmingCharacters(in:.whitespaces).isEmpty && !password.isEmpty }
    private var loggingIn: Bool { state == .loading }
    /// Primary dimmed until both fields are filled and while logging in; after 「没法直接登录」
    /// it is the web login and always available.
    private var dimmed: Bool { state != .cannotDirect && (loggingIn || !ready) }
    private var passwordSaved: Bool { preview.map { $0.password != nil } ?? campus.passwordSaved }
    private var savedAccount: SchoolAccount? { preview ?? campus.account }

    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            Button { dismiss() } label: {
                Image(systemName:"xmark").font(.system(size:15, weight:.semibold)).foregroundStyle(Theme.ink2)
                    .frame(width:36, height:36).background(Theme.fill, in:Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
            .padding(.top,18).padding(.leading,24)
            ScrollView {
                VStack(alignment:.leading, spacing:0) {
                    Text("登录学校账号").scaledFont(28, .bold, relativeTo:.largeTitle).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal:false, vertical:true)
                        .accessibilityAddTraits(.isHeader)
                    if !keyboardUp {
                        Text("用你在学校官网登录时的账号和密码。").scaledFont(17).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal:false, vertical:true).padding(.top,8)
                    }
                    SchoolLoginForm(account:$account, password:$password, savePassword:$savePassword,
                                    state:state, focus:$focus, submit:submit)
                        .padding(.top,keyboardUp ? 20 : 28)
                }
                .padding(.horizontal,24).padding(.top,24)
                if typeSize.isAccessibilitySize { bottom.padding(.top,40) }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge:.bottom, spacing:0) { if !typeSize.isAccessibilitySize { bottom.background(Theme.bg) } }
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
        .background(Theme.bg.ignoresSafeArea())
        .animation(reduceMotion ? .easeInOut(duration:0.2) : Theme.spring, value:keyboardUp)
        .tint(Theme.accentText)
        .typesettingLanguage(Theme.typesetting)
        .presentationDetents([.large])
        .interactiveDismissDisabled(loggingIn)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            account = (preview ?? campus.account)?.account ?? ""
            savePassword = passwordSaved
        }
        .onChange(of:account) { old, new in
            // Another account typed in: somebody else's password is not kept unless they tick it.
            savePassword = SchoolAccount.savePassword(savePassword, afterEditFrom:old, to:new, saved:savedAccount)
        }
        .sheet(isPresented:$webLogin) {
            CampusLoginSheet { value in
                do {
                    try await campus.adoptWebState(value)
                    await campus.refresh(force:true)
                    await signedIn()
                    dismiss()
                } catch {
                    state = .failed(error as? SchoolLoginFailure == .busy ? SchoolLoginText.busy : "这次没登录上，再试一次。")
                }
            }
        }
        // An account-switch alert waits until this sheet has closed.
        .holdsAccountSwitchAlert()
    }

    private var bottom: some View {
        VStack(spacing:0) {
            Button(action:primary) {
                HStack(spacing:10) {
                    if loggingIn { ProgressView().tint(Theme.ink2) }
                    Text(primaryTitle)
                }
                .scaledFont(18, .semibold, relativeTo:.headline)
                .foregroundStyle(dimmed ? (loggingIn ? Theme.ink2 : Theme.ink3) : Theme.pillInk)
                .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                .padding(.horizontal,20).padding(.vertical,8)
                .frame(maxWidth:.infinity, minHeight:keyboardUp ? 52 : 60)
                .background(dimmed ? Theme.fill : Theme.pill, in:Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(dimmed)
            .accessibilityIdentifier("reloginPrimary")
            if !keyboardUp && state != .cannotDirect {
                Button(SchoolLoginText.webLogin) { openWebLogin() }
                    .scaledFont(17, .medium).foregroundStyle(Theme.ink2)
                    .frame(minHeight:44).padding(.top,4)
                    .disabled(loggingIn)
                    .accessibilityIdentifier("reloginWeb")
            }
        }
        .padding(.horizontal,20)
        .padding(.bottom,keyboardUp ? 12 : 4)
    }

    private var primaryTitle: String {
        if loggingIn { return "正在登录…" }
        return state == .cannotDirect ? SchoolLoginText.webLogin : "登录"
    }

    private func primary() {
        if state == .cannotDirect { openWebLogin() } else { submit() }
    }

    /// One login, never retried (failures count towards the school's lock).
    private func submit() {
        guard ready, !loggingIn, state != .cannotDirect else { return }
        if preview != nil { return }
        focus = nil
        state = .loading
        let name = account.trimmingCharacters(in:.whitespaces), secret = password, save = savePassword
        Task {
            do {
                try await campus.signIn(account:name, password:secret, savePassword:save)
                password = ""
                await campus.refresh(force:true)
                await signedIn()
                state = .idle
                dismiss()
            } catch SchoolLoginFailure.wrongCredentials {
                password = ""
                state = .wrong
                focus = .password
            } catch SchoolLoginFailure.cannotLoginDirectly {
                state = .cannotDirect
            } catch {
                state = .failed(SchoolLoginText.text(error))
            }
        }
    }

    private func openWebLogin() {
        focus = nil
        if preview != nil { return }
        webLogin = true
    }
}
