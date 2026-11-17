import SwiftUI
import Core

/// Copy for the school login, both themes. The cause lines, the school-site button and the
/// web-login link are all here, so final copy is swapped in one place.
enum SchoolLoginText {
    static let wrong = "账号或密码不对，再试一次。"
    static let saveTitle = "保存密码，让小组件自动刷新"
    static let saveNote = "密码只存在这台 iPhone 的钥匙串里，不会上传。不保存的话，过几个小时小组件就要打开 App 才能更新。"
    /// The widget is refreshing (and may be logging in itself): nothing was sent.
    static let busy = "正在更新，等一下再试。"
    /// The Keychain refused to store the login's device id: nothing was sent.
    static let cannotSave = "登录信息没存上，再试一次。"
    /// VoiceOver hint of the web-login link.
    static let webLoginHint = "打开学校官网登录页"

    /// The small link under the form.
    static func webLogin(_ theme: AppTheme) -> String {
        theme == .clear ? "使用学校网页登录" : "用学校网页登录"
    }

    /// The button that opens the school's login page in Safari (`needsSchoolSite`).
    static func schoolSite(_ theme: AppTheme) -> String {
        theme == .clear ? "前往学校官网" : "去学校官网处理"
    }

    /// Why a password login was not taken, when the school did not call it wrong.
    static func blocked(_ cause: SchoolLoginCause, theme: AppTheme) -> String {
        switch (cause, theme) {
        case (.locked, .warm): return "错的次数太多，学校把账号锁了。等 5 分钟再登。"
        case (.locked, .clear): return "账号已被锁定，请 5 分钟后再登录"
        case (.needsSchoolSite, .warm): return "学校要你先在官网处理一下，比如验证或改密码。弄好了回来再登。"
        case (.needsSchoolSite, .clear): return "学校要求先在官网完成验证或修改密码，完成后返回重新登录"
        case (.unknown, .warm): return "这次没法直接登录，可能是学校登录页变了。过一会儿再试，急的话用下面的学校网页登录。"
        case (.unknown, .clear): return "暂时无法直接登录，可稍后重试或使用学校网页登录"
        }
    }

    /// The primary button of every login form: always the password login.
    static func primary(loggingIn: Bool) -> String { loggingIn ? "正在登录…" : "登录" }

    /// Anything other than the two login answers (network, storage, the card steps after login).
    static func text(_ error: Error, theme: AppTheme = .warm) -> String {
        switch error as? SchoolLoginFailure {
        case .wrongCredentials?: return wrong
        case .cannotLoginDirectly(let block)?: return blocked(SchoolLoginCause(block), theme:theme)
        case .offline?, .noAnswer?: return ServiceError.offline.userMessage
        case .differentAccount?, .unreadableAccount?: return (error as? SchoolLoginFailure)?.savePasswordRefusal?.text ?? ""
        case .busy?: return busy
        case .cannotSave?: return cannotSave
        case nil: return AppErrorText.text(error)
        }
    }
}

/// What the form says when the school would not take the password and did not call it wrong.
enum SchoolLoginCause: Equatable {
    /// Wait 5 minutes (the school's lock); the form stays as it is.
    case locked
    /// Captcha, extra check, password change or activation: 「去学校官网处理」 opens Safari.
    case needsSchoolSite
    /// A page we don't recognise: try later, or the web-login link under the form.
    case unknown

    init(_ block: SchoolLoginBlock) {
        switch block {
        case .locked: self = .locked
        case .unknown: self = .unknown
        case .captcha, .mfa, .passwordChange: self = .needsSchoolSite
        }
    }
}

/// What the login form shows under the fields.
enum SchoolLoginState: Equatable {
    case idle, loading
    /// Wrong account or password: the password is cleared and focused.
    case wrong
    /// The school put something in the way: said by cause. The password login stays the
    /// primary button and can be tried again.
    case blocked(SchoolLoginCause)
    /// Network or storage trouble; the form stays as it was.
    case failed(String)

    /// The form's next state after a failed login.
    init(after error: Error) {
        switch error as? SchoolLoginFailure {
        case .wrongCredentials?: self = .wrong
        case .cannotLoginDirectly(let block)?: self = .blocked(SchoolLoginCause(block))
        default: self = .failed(SchoolLoginText.text(error))
        }
    }

    func message(_ theme: AppTheme) -> String? {
        switch self {
        case .idle, .loading: return nil
        case .wrong: return SchoolLoginText.wrong
        case .blocked(let cause): return SchoolLoginText.blocked(cause, theme:theme)
        case .failed(let text): return text
        }
    }

    /// The typed password was used up: signed in, or refused as wrong (typed again from empty).
    var clearsTypedPassword: Bool { self == .idle || self == .wrong }

    /// 「保存密码」 shows except when the next step is the school's site or its web login,
    /// which save no password; a lock keeps it (the same login is tried again later).
    var showsSaveCheck: Bool {
        switch self {
        case .blocked(.needsSchoolSite), .blocked(.unknown): return false
        default: return true
        }
    }

    /// 「去学校官网处理」 under the line.
    var offersSchoolSite: Bool { self == .blocked(.needsSchoolSite) }

    /// The password login can be sent (every state but one already going).
    var allowsDirectLogin: Bool { self != .loading }
}

enum SchoolLoginField: Hashable { case account, password }

/// Account / password rows, the error line and the save-password check.
struct SchoolLoginForm: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var account: String
    @Binding var password: String
    @Binding var savePassword: Bool
    let state: SchoolLoginState
    var focus: FocusState<SchoolLoginField?>.Binding
    var submit: () -> Void
    /// The small 「用学校网页登录」 link under the form.
    var webLogin: () -> Void
    @State private var reveal = false

    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            VStack(spacing:0) {
                row("账号") {
                    TextField("", text:$account, prompt:Text("输入账号").foregroundStyle(Theme.ink2))
                        .textContentType(.username)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused(focus, equals:.account)
                        .onSubmit { focus.wrappedValue = .password }
                        .accessibilityIdentifier("loginAccount")
                }
                Hairline().padding(.leading,16)
                row("密码") {
                    Group {
                        if reveal {
                            TextField("", text:$password, prompt:Text("输入密码").foregroundStyle(Theme.ink2))
                        } else {
                            SecureField("", text:$password, prompt:Text("输入密码").foregroundStyle(Theme.ink2))
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused(focus, equals:.password)
                    .onSubmit(submit)
                    .accessibilityIdentifier("loginPassword")
                    Button {
                        let typing = focus.wrappedValue == .password
                        reveal.toggle()
                        // Swapping the field drops focus; keep the keyboard where it was.
                        if typing { focus.wrappedValue = .password }
                    } label: {
                        Image(systemName:reveal ? "eye" : "eye.slash")
                            .font(.system(size:20)).foregroundStyle(Theme.ink2)
                            .frame(width:44, height:44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reveal ? "隐藏密码" : "显示密码")
                }
            }
            .background(Theme.group, in:RoundedRectangle(cornerRadius:appTheme.cardRadius(16), style:.continuous))
            .opacity(state == .loading ? 0.5 : 1)
            .disabled(state == .loading)
            if let message = state.message(appTheme) {
                // Not red: red means something is running out.
                Label { Text(message).fixedSize(horizontal:false, vertical:true) } icon: {
                    Image(systemName:"exclamationmark.circle.fill").font(.system(size:17))
                }
                .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.notice)
                .padding(.top,14)
                .accessibilityIdentifier("loginIssue")
            }
            if state.offersSchoolSite {
                SchoolSiteButton().padding(.top,10)
            }
            // After 「没法直接登录」 (not a lock) the next step is the school's site or its web
            // login, which save no new password.
            if state.showsSaveCheck { saveCheck }
            SchoolWebLoginLink(action:webLogin)
                .disabled(state == .loading)
                .padding(.top,12)
        }
    }

    private var saveCheck: some View {
        Toggle(isOn:$savePassword) {
            VStack(alignment:.leading, spacing:4) {
                Text(SchoolLoginText.saveTitle).scaledFont(16, .medium).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal:false, vertical:true)
                Text(SchoolLoginText.saveNote).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
            }
        }
        .toggleStyle(CheckToggleStyle())
        .disabled(state == .loading)
        .padding(.top,18)
        .accessibilityIdentifier("savePassword")
    }

    private func row<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing:0) {
            Text(label).scaledFont(17, .medium).foregroundStyle(Theme.ink)
                .frame(minWidth:56, alignment:.leading).fixedSize()
            field().scaledFont(17).foregroundStyle(Theme.ink)
        }
        .padding(.leading,16).padding(.trailing,4)
        .frame(minHeight:52)
    }
}

/// A round check in front of the label; the whole row toggles.
struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment:.top, spacing:12) {
                CheckMark(on:configuration.isOn)
                configuration.label
                Spacer(minLength:0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children:.combine)
        .accessibilityValue(configuration.isOn ? "已勾选" : "未勾选")
    }
}

private struct CheckMark: View {
    let on: Bool
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        ZStack {
            if on {
                Circle().fill(Theme.accentText)
                Image(systemName:"checkmark").font(.system(size:12, weight:.bold))
                    // White in light, #111 in dark, resolved by the asset from the trait collection.
                    .foregroundStyle(Theme.accentInk)
            } else {
                Circle().strokeBorder(Theme.ink3, lineWidth:1.5)
            }
        }
        .frame(width:22, height:22)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityHidden(true)
    }
}
