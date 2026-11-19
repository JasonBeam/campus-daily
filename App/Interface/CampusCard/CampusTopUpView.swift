import SwiftUI
import UIKit
import Core

/// 校园充值: one page for the campus card and the electricity. 「打开微信」 copies the name of the
/// school's WeChat service, then opens WeChat; no money goes through the app. Back in the app
/// after WeChat, the balances are read again once in the background.
/// 清爽 has its own page (`ClearCampusTopUpView`).
struct CampusTopUpView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SampleMode.self) private var sample
    @Environment(\.campusServices) private var services
    @EnvironmentObject private var campus: CampusModel
    @State private var flow: CampusTopUpFlow?

    var body: some View {
        if appTheme == .clear { ClearCampusTopUpView() } else { warm }
    }

    private var warm: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:0) {
                Image(systemName:"arrow.up.forward.app").font(.system(size:32))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(CampusTopUpText.headline).font(.title2.bold()).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal:false, vertical:true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top,16)
                Text(CampusTopUpText.body).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.top,10)
                Text(CampusTopUpText.hint).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false, vertical:true)
                    .accessibilityIdentifier("campusTopUpHint")
                    .padding(.top,10)
                Button { send(.weChatTapped) } label: {
                    Text(CampusTopUpText.openWeChat).font(.body.weight(.semibold))
                        .foregroundStyle(Theme.pillInk)
                        .frame(maxWidth:.infinity, minHeight:50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.pill.color(appTheme))
                .accessibilityIdentifier("campusTopUpWeChat")
                .padding(.top,28)
                statusLine.padding(.top,12)
            }
            .padding(.horizontal,20).padding(.top,32).padding(.bottom,20)
            .frame(maxWidth:560, alignment:.leading)
            .frame(maxWidth:.infinity)
        }
        .background { Theme.bg.ignoresSafeArea() }
        .navigationTitle(CampusTopUpText.title)
        .navigationBarTitleDisplayMode(.inline)
        .typesettingLanguage(Theme.typesetting)
        .onChange(of:scenePhase) { _, phase in send(.scene(active:phase == .active)) }
    }

    /// Right under the button, so VoiceOver reads it next; kept for when the user comes back.
    @ViewBuilder private var statusLine: some View {
        switch current.line {
        case .none:
            EmptyView()
        case .copied:
            HStack(alignment:.firstTextBaseline, spacing:6) {
                Image(systemName:"checkmark.circle").accessibilityHidden(true)
                Text(CampusTopUpText.copied).fixedSize(horizontal:false, vertical:true)
            }
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityElement(children:.combine)
            .accessibilityIdentifier("campusTopUpCopied")
        case .weChatFailed:
            HStack(alignment:.firstTextBaseline, spacing:6) {
                Image(systemName:"exclamationmark.circle").accessibilityHidden(true)
                Text(CampusTopUpText.failed).fixedSize(horizontal:false, vertical:true)
            }
            .font(.footnote).foregroundStyle(Theme.notice)
            .accessibilityElement(children:.combine)
            .accessibilityIdentifier("campusTopUpFailed")
        }
    }

    private var accent: ThemeColor { Theme.accentText }

    private var current: CampusTopUpFlow { flow ?? CampusTopUpFlow(sample:sample.isActive) }

    private func send(_ event: CampusTopUpEvent) {
        var next = current
        let effects = next.handle(event)
        flow = next
        for effect in effects {
            switch effect {
            case .copy(let text):
                // Before the open below: WeChat takes the app out of the front.
                UIPasteboard.general.string = text
            case .open(let url):
                Task {
                    let opened = await UIApplication.shared.open(url)
                    services.debugLog.record(.topUpWeChat(opened:opened))
                    send(.weChatOpened(opened))
                }
            case .announceFailure:
                AccessibilityNotification.Announcement(CampusTopUpText.failed).post()
            case .refreshBalances:
                // Nothing on screen: the numbers on home change when it lands.
                Task { await campus.refresh(force:true) }
            }
        }
    }
}

/// Copy for 校园充值.
enum CampusTopUpText {
    static let title = "校园充值"
    static let headline = "去学校的微信服务充值"
    static let body = "校园卡和电费都在学校的「e广工商大办事大厅」里充。进去后选校园卡或电费，付款前核对一下宿舍和金额。"
    /// Above the button: what the tap does and where to find the service in WeChat.
    static let hint = "点了会先复制「e广工商大办事大厅」再打开微信。在聊天列表往下拉，点它就行；没看到的话，点搜索粘贴进去。"
    static let openWeChat = "打开微信"
    /// Under the button once the name is copied.
    static let copied = "已复制 e广工商大办事大厅"
    /// Under the button when WeChat does not open (the name is still copied).
    static let failed = "微信没打开，名字已经复制好了。自己打开微信，点搜索粘贴进去。"
}
