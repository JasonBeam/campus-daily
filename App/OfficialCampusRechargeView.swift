import SwiftUI
import UIKit

struct OfficialCampusRechargeView: View {
    @EnvironmentObject private var campus: CampusModel
    @Environment(\.scenePhase) private var phase
    @State private var attempted = false
    @State private var issue: String?
    // Issued by the school's own mini-program through Add to Home Screen;
    // verified on iPhone, not assembled from an order or login token.
    private let scheme = URL(string:"weixin://dl/business/?t=I0xUgrvZt1g")!
    private let officialPage = URL(string:"https://wxmpurl.cn/I0xUgrvZt1g")!
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Label("前往学校官方微信服务",systemImage:"arrow.up.forward.app").font(.title2.bold())
            Text("进入“e广工商大办事大厅”后，选择校园卡或电费充值；充值电费时请核对宿舍和金额。")
            Text("校日常只负责打开学校入口。付款和到账以学校官方结果为准；返回后会刷新余额。")
                .font(.footnote).foregroundStyle(.secondary)
            Button("打开学校微信入口") { openSchool() }.buttonStyle(.borderedProminent)
                .accessibilityIdentifier("openOfficialCampusWeChat")
            if let issue { Text(issue).font(.footnote).foregroundStyle(.orange) }
            Button("使用学校官方中转页") { UIApplication.shared.open(officialPage) }
                .accessibilityIdentifier("openOfficialCampusWebFallback")
            Text("若入口失效，可在微信搜索“e广工商大办事大厅”，或使用学校官方小程序码。")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
            .navigationTitle("校园充值").navigationBarTitleDisplayMode(.inline)
            .task { if !attempted { openSchool() } }
            .onChange(of:phase) { _,value in
                if value == .active && attempted { Task { await campus.refresh(force:true) } }
            }
    }
    private func openSchool() {
        attempted = true; issue = nil
        UIApplication.shared.open(scheme) { opened in
            if !opened { issue = "未能打开微信，请确认已安装微信，或使用下方官方中转页。" }
        }
    }
}
