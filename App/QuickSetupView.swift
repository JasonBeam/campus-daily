import SwiftUI

struct QuickSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var water: WaterModel
    @EnvironmentObject private var laundry: LaundryModel
    private var washerDone: Bool { laundry.accountConnected && !laundry.savedMachines.isEmpty }
    private var completed: Int { (campus.configured ? 1 : 0) + (water.configured ? 1 : 0) + (washerDone ? 1 : 0) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                VStack(alignment:.leading,spacing:12) {
                    Text("已完成 \(completed) / 3").font(.subheadline).foregroundStyle(.secondary)
                    Text(completed == 3 ? "都准备好了" : "完成首次设置").font(.title.bold())
                    Text(!campus.configured ? "先登录学校账号，再选择宿舍和常用洗衣机。" : !water.configured ? "学校账号已登录，接着选择你的宿舍。" : "宿舍已保存，接着绑定常用洗衣机。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value:Double(completed),total:3).tint(NativeTheme.tint)
                        .accessibilityLabel("首次设置进度").accessibilityValue("已完成 \(completed) 项，共三项")
                }
                VStack(spacing:0) {
                    NavigationLink { CampusOnboardingView() } label: {
                        row("学校账号",detail:campus.configured ? "已登录，可查询校园卡余额" : "登录后自动同步校园卡余额",done:campus.configured,symbol:"person.crop.circle")
                    }.accessibilityIdentifier("quickSetupCampus")
                    Divider().padding(.leading,54)
                    NavigationLink { CampusOnboardingView() } label: {
                        row("选择宿舍与水控",detail:water.configured ? campus.room : "选择楼栋房间，确认自己的设备",done:water.configured,symbol:"building.2")
                    }.accessibilityIdentifier("quickSetupWater")
                    Divider().padding(.leading,54)
                    NavigationLink { WasherSetupView() } label: {
                        row("绑定洗衣机",detail:washerDone ? "已保存 \(laundry.savedMachines.count) 台机器" : "登录 U净，扫码保存常用机器",done:washerDone,symbol:"washer")
                    }.accessibilityIdentifier("quickSetupWasher")
                }.buttonStyle(.plain).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                if completed == 3 {
                    Button("完成设置") { dismiss() }.buttonStyle(NothingButtonStyle())
                } else if !campus.configured || !water.configured {
                    NavigationLink { CampusOnboardingView() } label: { Text(campus.configured ? "继续选择宿舍" : "登录并连接校园卡") }
                        .buttonStyle(NothingButtonStyle())
                } else {
                    NavigationLink { WasherSetupView() } label: { Text(laundry.accountConnected ? "扫描洗衣机二维码" : "登录 U净") }
                        .buttonStyle(NothingButtonStyle())
                }
                NavigationLink { CampusPowerSetupView() } label: {
                    HStack {
                        VStack(alignment:.leading,spacing:6) {
                            Text("宿舍电费与小组件").font(.subheadline.weight(.medium))
                            Text(campus.powerConfigured ? "电表已绑定，可更换" : "可选，完成后也能设置").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName:"chevron.right").font(.caption)
                    }.padding(16).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                }.buttonStyle(.plain).disabled(!campus.configured)
                Text("这里只读取和保存配置，不会出水、下单或付款。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(NativeTheme.background).tint(NativeTheme.tint)
            .navigationTitle("首次配置").navigationBarTitleDisplayMode(.inline)
    }
    private func row(_ title: String,detail: String,done: Bool,symbol: String) -> some View {
        HStack(alignment:.center,spacing:14) {
            Image(systemName:done ? "checkmark.circle.fill" : symbol).font(.title3).foregroundStyle(NativeTheme.tint).frame(width:24).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:4)
            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }.padding(16).frame(minHeight:76).contentShape(Rectangle()).accessibilityElement(children:.combine)
    }
}
