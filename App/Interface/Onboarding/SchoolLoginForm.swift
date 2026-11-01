import SwiftUI
import Core

/// Copy for the school login.
enum SchoolLoginText {
    static let wrong = "账号或密码不对，再试一次。"
    static let cannotDirect = "这次没法直接登录，换学校网页登录试试。"
    static let webLogin = "用学校网页登录"
    static let saveTitle = "保存密码，让小组件自动刷新"
    static let saveNote = "密码只存在这台 iPhone 的钥匙串里，不会上传。不保存的话，过几个小时小组件就要打开 App 才能更新。"
    /// The widget is refreshing (and may be logging in itself): nothing was sent.
    static let busy = "正在更新，等一下再试。"

    /// Anything other than the two login answers (network, storage, the card steps after login).
    static func text(_ error: Error) -> String {
        switch error as? SchoolLoginFailure {
        case .wrongCredentials?: return wrong
        case .cannotLoginDirectly?: return cannotDirect
        case .offline?, .noAnswer?: return ServiceError.offline.userMessage
        case .differentAccount?, .unreadableAccount?: return (error as? SchoolLoginFailure)?.savePasswordRefusal?.text ?? ""
        case .busy?: return busy
        case nil: return AppErrorText.text(error)
        }
    }
}

/// What the login form shows under the fields.
enum SchoolLoginState: Equatable {
    case idle, loading
    /// Wrong account or password: the password is cleared and focused.
    case wrong
    /// Captcha, lock or anything unrecognised: the primary button becomes 「用学校网页登录」.
    case cannotDirect
    /// Network or storage trouble; the form stays as it was.
    case failed(String)

    var message: String? {
        switch self {
        case .idle, .loading: return nil
        case .wrong: return SchoolLoginText.wrong
        case .cannotDirect: return SchoolLoginText.cannotDirect
        case .failed(let text): return text
        }
    }
}

enum SchoolLoginField: Hashable { case account, password }

/// Account / password rows, the error line and the save-password check.
struct SchoolLoginForm: View {
    @Binding var account: String
    @Binding var password: String
    @Binding var savePassword: Bool
    let state: SchoolLoginState
    var focus: FocusState<SchoolLoginField?>.Binding
    var submit: () -> Void
    @State private var reveal = false

    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            VStack(spacing:0) {
                row("账号") {
                    TextField("", text:$account, prompt:Text("输入账号").foregroundStyle(Theme.ink3))
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
                            TextField("", text:$password, prompt:Text("输入密码").foregroundStyle(Theme.ink3))
                        } else {
                            SecureField("", text:$password, prompt:Text("输入密码").foregroundStyle(Theme.ink3))
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
            .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
            .opacity(state == .loading ? 0.5 : 1)
            .disabled(state == .loading)
            if let message = state.message {
                // Not red: red means something is running out.
                Label { Text(message).fixedSize(horizontal:false, vertical:true) } icon: {
                    Image(systemName:"exclamationmark.circle.fill").font(.system(size:17))
                }
                .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.accentText)
                .padding(.top,14)
                .accessibilityIdentifier("loginIssue")
            }
            // After 「没法直接登录」 the next step is the web login, which saves no new password.
            if state != .cannotDirect { saveCheck }
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
