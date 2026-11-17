import SwiftUI
import UIKit

struct OfficialCampusRechargeView: View {
    @EnvironmentObject private var campus: CampusModel
    @Environment(\.scenePhase) private var phase
    @State private var attempted = false
    @State private var issue: String?
    private let serviceName = "e广工商大办事大厅"
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Label("前往学校官方微信服务",systemImage:"arrow.up.forward.app").font(.title2.bold())
            Text("进入“e广工商大办事大厅”后，选择校园卡或电费充值；充值电费时请核对宿舍和金额。")
            Text("请在微信中搜索下方服务名称。付款和到账以学校官方结果为准；返回后会刷新余额。")
                .font(.footnote).foregroundStyle(.secondary)
            Button("打开微信，搜索学校服务") { openSchool() }.buttonStyle(.borderedProminent)
                .accessibilityIdentifier("openOfficialCampusWeChat")
            if let issue { Text(issue).font(.footnote).foregroundStyle(.orange) }
            Button("复制学校服务名称") {
                UIPasteboard.general.string = serviceName
                issue = "已复制，请在微信中搜索“\(serviceName)”。"
            }.accessibilityIdentifier("copyOfficialCampusServiceName")
            NavigationLink("查看学校官方小程序码") { SchoolMiniProgramCodeView() }
            Text("微信 → 搜索“e广工商大办事大厅” → 核对学校身份后进入充值。也可使用学校正式提供的小程序码。")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
            .navigationTitle("校园充值").navigationBarTitleDisplayMode(.inline)
            .onChange(of:phase) { _,value in
                if value == .active && attempted { Task { await campus.refresh(force:true) } }
            }
    }
    private func openSchool() {
        attempted = true; issue = nil
        UIApplication.shared.open(URL(string:"weixin://")!) { opened in
            if !opened { issue = "未能打开微信，请手动打开微信并搜索学校服务名称。" }
        }
    }
}

private struct SchoolMiniProgramCodeView: View {
    @State private var sharing=false
    var body: some View {
        ScrollView {
            VStack(alignment:.center,spacing:20) {
                Text("e广工商大办事大厅").font(.headline)
                Image("SchoolMiniProgramCode").resizable().interpolation(.high).scaledToFit()
                    .frame(maxWidth:280).padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius:16))
                Text("保存或截图后，在微信扫一扫中从相册选择识别。进入后核对学校名称和认证主体。")
                Button("保存或分享小程序码") {sharing=true}.buttonStyle(.borderedProminent)
                Link("查看学校官网使用说明",destination:URL(string:"https://xxzxo.gdbtu.edu.cn/contents/3039/51848.html")!)
                Text("来源：学校信息技术中心。首次进入后可添加到微信“我的小程序”，下次从微信下拉即可找到。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.navigationTitle("学校官方小程序码").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$sharing) { SchoolCodeShare() }
    }
}
private struct SchoolCodeShare: UIViewControllerRepresentable {
    func makeUIViewController(context:Context)->UIActivityViewController {
        UIActivityViewController(activityItems:UIImage(named:"SchoolMiniProgramCode").map{[$0]} ?? [],applicationActivities:nil)
    }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
