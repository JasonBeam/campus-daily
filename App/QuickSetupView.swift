import SwiftUI

struct QuickSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var water: WaterModel
    @EnvironmentObject private var laundry: LaundryModel
    var body: some View {
        List {
            Section {
                Text("把校园账号、宿舍和常用洗衣机留在自己的手机里。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink { CampusOnboardingView() } label: {
                    row("校园账号与热水宿舍",detail:campus.configured && water.configured ? "已配置 · 可重新选择" : "登录学校账号，选择自己的宿舍",symbol:"person.crop.circle",done:campus.configured && water.configured)
                }.accessibilityIdentifier("quickSetupCampus")
                NavigationLink { WasherSetupView() } label: {
                    row("常用洗衣机",detail:laundry.accountConnected ? "已登录 · 扫码添加机器" : "登录 U净，扫描机身二维码",symbol:"qrcode.viewfinder",done:laundry.configured && !laundry.savedMachines.isEmpty)
                }.accessibilityIdentifier("quickSetupWasher")
            } footer: {
                Text("校园账号和 U净是两个独立账号。设置过程不会出水、下单或付款。")
            }
        }.navigationTitle("快速设置").navigationBarTitleDisplayMode(.inline)
    }
    private func row(_ title: String, detail: String, symbol: String, done: Bool) -> some View {
        HStack(spacing:14) {
            Image(systemName:symbol).font(.title2).foregroundStyle(.tint).frame(width:32)
            VStack(alignment:.leading,spacing:6) {
                Text(title).font(.headline)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if done { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("已配置") }
        }.padding(.vertical,10)
    }
}
