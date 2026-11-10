import SwiftUI
import UIKit
import Core

/// 校园充值 in 清爽: what to do in the school's WeChat service, 「打开学校微信入口」 and the
/// school's web hand-off page. Nothing opens until a tap; back in the app after one, the
/// balances are read again once in the background (`CampusTopUpFlow`).
struct ClearCampusTopUpView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SampleMode.self) private var sample
    @EnvironmentObject private var campus: CampusModel
    @State private var flow: CampusTopUpFlow?

    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:20) {
                Label(ClearCampusTopUpText.headline, systemImage:"arrow.up.forward.app")
                    .font(.title2.bold())
                    .fixedSize(horizontal:false, vertical:true)
                    .accessibilityAddTraits(.isHeader)
                Text(ClearCampusTopUpText.body).fixedSize(horizontal:false, vertical:true)
                Text(ClearCampusTopUpText.note).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false, vertical:true)
                Button(ClearCampusTopUpText.openWeChat) { send(.weChatTapped) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("campusTopUpWeChat")
                if current.weChatFailed {
                    Text(ClearCampusTopUpText.failed).font(.footnote).foregroundStyle(.orange)
                        .fixedSize(horizontal:false, vertical:true)
                        .accessibilityIdentifier("campusTopUpFailed")
                }
                Button(ClearCampusTopUpText.openWeb) { send(.webTapped) }
                    .accessibilityIdentifier("campusTopUpWeb")
                Text(ClearCampusTopUpText.footnote).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false, vertical:true)
                    .accessibilityIdentifier("campusTopUpFootnote")
            }
            .padding(20)
            .frame(maxWidth:560, alignment:.leading)
            .frame(maxWidth:.infinity)
        }
        .tint(NativeTheme.tint)
        .navigationTitle(ClearCampusTopUpText.title)
        .navigationBarTitleDisplayMode(.inline)
        .typesettingLanguage(Theme.typesetting)
        .onChange(of:scenePhase) { _, phase in send(.scene(active:phase == .active)) }
    }

    private var current: CampusTopUpFlow { flow ?? CampusTopUpFlow(sample:sample.isActive) }

    private func send(_ event: CampusTopUpEvent) {
        var next = current
        let effects = next.handle(event)
        flow = next
        for effect in effects {
            switch effect {
            case .open(let url):
                Task {
                    let opened = await UIApplication.shared.open(url)
                    if url == CampusTopUp.weChat { send(.weChatOpened(opened)) }
                }
            case .announceFailure:
                AccessibilityNotification.Announcement(ClearCampusTopUpText.failed).post()
            case .refreshBalances:
                Task { await campus.refresh(force:true) }
            }
        }
    }
}

/// Copy for 清爽's 校园充值.
enum ClearCampusTopUpText {
    static let title = "校园充值"
    static let headline = "前往学校官方微信服务"
    static let body = "进入“e广工商大办事大厅”后，选择校园卡或电费充值；充值电费时请核对宿舍和金额。"
    static let note = "校日常只负责打开学校入口。付款和到账以学校官方结果为准；返回后会刷新余额。"
    static let openWeChat = "打开学校微信入口"
    static let failed = "未能打开微信，请确认已安装微信，或使用下方官方中转页。"
    static let openWeb = "使用学校官方中转页"
    static let footnote = "若入口失效，可在微信搜索“e广工商大办事大厅”，或使用学校官方小程序码。"
}
