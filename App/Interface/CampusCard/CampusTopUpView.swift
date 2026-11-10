import SwiftUI
import UIKit
import Core

/// 校园充值: one page for the campus card and the electricity. It only opens the school's
/// WeChat service (or the school's web hand-off page in Safari); no money goes through the app.
/// Back in the app after either button, the balances are read again once in the background.
/// 清爽 has its own page (`ClearCampusTopUpView`).
struct CampusTopUpView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SampleMode.self) private var sample
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
                Button { send(.webTapped) } label: {
                    Text(CampusTopUpText.openWeb).font(.body)
                        .foregroundStyle(accent)
                        .frame(maxWidth:.infinity, minHeight:44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(accent.color(appTheme))
                .accessibilityIdentifier("campusTopUpWeb")
                .padding(.top,10)
                footnote.padding(.top,12)
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

    @ViewBuilder private var footnote: some View {
        if current.weChatFailed {
            HStack(alignment:.firstTextBaseline, spacing:6) {
                Image(systemName:"exclamationmark.circle").accessibilityHidden(true)
                Text(CampusTopUpText.failed).fixedSize(horizontal:false, vertical:true)
            }
            .font(.footnote).foregroundStyle(Theme.notice)
            .accessibilityElement(children:.combine)
            .accessibilityIdentifier("campusTopUpFailed")
        } else {
            Text(CampusTopUpText.footnote).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal:false, vertical:true)
                .accessibilityIdentifier("campusTopUpFootnote")
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
            case .open(let url):
                // Opened outside the app: WeChat, or the school's page in Safari.
                Task {
                    let opened = await UIApplication.shared.open(url)
                    if url == CampusTopUp.weChat { send(.weChatOpened(opened)) }
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
    static let openWeChat = "打开微信"
    static let openWeb = "用网页打开"
    static let footnote = "微信打不开的话，点「用网页打开」，或者在微信里搜「e广工商大办事大厅」。"
    static let failed = "微信没打开。点「用网页打开」，或者在微信里搜「e广工商大办事大厅」。"
}
