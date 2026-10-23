import SwiftUI
import UniformTypeIdentifiers
import WaterCore

@main struct CampusHotWaterApp: App {
    @StateObject private var water = WaterModel.shared
    @StateObject private var campus = CampusModel()
    @StateObject private var laundry = LaundryModel()
    var body: some Scene {
        WindowGroup {
            WaterHome().environmentObject(water).environmentObject(campus).environmentObject(laundry)
                .task {
                    water.importDevelopmentConfigIfPresent()
                    campus.importDevelopmentConfigIfPresent()
                    laundry.importDevelopmentConfigIfPresent()
                    await laundry.recoverDevelopmentOrderIfPresent()
                    await campus.refresh()
                    await laundry.refresh()
                }
                .onOpenURL { AlipayBridge.shared.handle($0); Task { await laundry.refreshOrder() } }
        }
    }
}

struct WaterHome: View {
    @EnvironmentObject private var water: WaterModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(\.scenePhase) private var phase
    @State private var settings = false
    @State private var firstRun = false
    @AppStorage("didSeeQuickSetup") private var didSeeQuickSetup = false
    @ScaledMetric(relativeTo:.largeTitle) private var balanceSize: CGFloat = 48
    private let accent = Color(red:0.10,green:0.35,blue:0.68)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    balanceCard
                    HStack {
                        Text("日常服务").font(.title3.weight(.semibold))
                        Spacer()
                        Text("点开即用").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal,4)
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.top,spacing:14) { waterTile.frame(minWidth:155); laundryTile.frame(minWidth:155) }
                        VStack(spacing:14) { waterTile; laundryTile }
                    }
                    if let record = laundry.checkout, record.stage != .completed {
                        NavigationLink { LaundryDetail() } label: {
                            HStack(spacing:14) {
                                Image(systemName:"clock.arrow.circlepath").font(.title2)
                                VStack(alignment:.leading,spacing:5) {
                                    Text("洗衣订单").font(.headline)
                                    Text(record.order?.label ?? "订单结果待核对").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName:"chevron.right").font(.caption)
                            }.padding(20).foregroundStyle(.primary)
                                .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:24))
                        }.buttonStyle(.plain)
                    }
                    if let ended = water.lastEnded {
                        HStack(alignment:.top,spacing:12) {
                            Image(systemName:"checkmark.circle").foregroundStyle(.secondary)
                            VStack(alignment:.leading,spacing:5) {
                                Text("上次热水已结算").font(.subheadline.weight(.medium))
                                Text(ended.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let cost = water.lastCost { Text(cost,format:.currency(code:"CNY")).font(.subheadline.weight(.semibold)).monospacedDigit() }
                        }.padding(.horizontal,4)
                    }
                }.padding(.horizontal,20).padding(.top,12).padding(.bottom,28)
                    .frame(maxWidth:560).frame(maxWidth:.infinity)
            }.background(Color(uiColor:.systemGroupedBackground))
                .navigationTitle("校园生活").navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement:.topBarTrailing) {
                        Button { settings = true } label: { Image(systemName:"gearshape").frame(width:44,height:44) }
                            .accessibilityLabel("设置与个人配置")
                    }
                }
                .refreshable { await campus.refresh(force:true); await laundry.refresh(force:true) }
                .sheet(isPresented:$settings) { SettingsView() }
                .sheet(isPresented:$firstRun,onDismiss:{ didSeeQuickSetup = true }) {
                    NavigationStack {
                        QuickSetupView().toolbar {
                            ToolbarItem(placement:.confirmationAction) { Button("稍后设置") { firstRun = false } }
                        }
                    }
                }
                .task {
                    if !didSeeQuickSetup && !campus.configured && !water.configured && !laundry.configured { firstRun = true }
                }
                .onChange(of:phase) { _,value in
                    if value == .active { Task { await campus.refresh(); await laundry.refresh(); await laundry.refreshOrder() } }
                }
                .onChange(of:water.stage) { old,value in
                    if old != .settled, value == .settled { Task { await campus.refresh(force:true) } }
                }
        }.tint(accent)
    }
    private var waterTile: some View {
        NavigationLink { WaterDetail() } label: {
            ServiceTile(title:"热水洗澡",symbol:"drop.fill",status:water.busy ? "处理中" : water.problem ? "待核对" : !water.configured ? "待配置" : water.stage?.mayClose == true ? "用水中" : "随时可用",
                detail:water.stage?.mayClose == true ? "结束后记得结算" : "开始 · 结束结算",color:accent)
        }.buttonStyle(.plain).accessibilityIdentifier("waterEntry")
    }
    private var laundryTile: some View {
        NavigationLink { LaundryDetail() } label: {
            ServiceTile(title:"洗衣机",symbol:"washer.fill",status:laundry.deviceStateText,
                detail:laundry.snapshot.map { "\($0.deviceNo)号 · \($0.storeName)" } ?? "常用机器 · 选择程序",color:Color(red:0.37,green:0.31,blue:0.65))
        }.buttonStyle(.plain).accessibilityIdentifier("laundryEntry")
    }
    private var balanceCard: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                Label("校园卡余额",systemImage:"creditcard").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing:5) {
                    if campus.loading { ProgressView().controlSize(.mini) }
                    Text(campus.freshness)
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment:.firstTextBaseline,spacing:5) {
                Text("¥").font(.title2.weight(.medium)).foregroundStyle(.secondary)
                Text(campus.balanceText).font(.system(size:balanceSize,weight:.semibold,design:.rounded))
                    .monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
                    .accessibilityIdentifier("campusBalance")
            }.accessibilityElement(children:.ignore)
                .accessibilityLabel("校园卡余额 \(campus.balanceText == "—" ? "暂未获取" : campus.balanceText + "元")")
            Divider()
            HStack(alignment:.firstTextBaseline,spacing:12) {
                Label("宿舍",systemImage:"building.2").foregroundStyle(.secondary)
                Spacer(minLength:8)
                Text(campus.room).fontWeight(.medium).multilineTextAlignment(.trailing)
                    .textSelection(.enabled).accessibilityIdentifier("dormRoom")
            }.font(.subheadline)
            if let issue = campus.issue {
                Text(issue).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
            }
            if let date = campus.snapshot?.balanceFetchedAt {
                Text("查询于 \(date.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.tertiary)
            } else {
                Text(campus.configured ? "下拉可更新余额" : "在设置中导入校园卡配置").font(.caption).foregroundStyle(.tertiary)
            }
        }.padding(22).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:24))
    }

}

struct WaterDetail: View {
    @EnvironmentObject private var water: WaterModel
    private let accent = Color(red:0.10,green:0.35,blue:0.68)
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                waterCard
                Label("开始后按设备出水键，结束后确认已停水。",systemImage:"info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(Color(uiColor:.systemGroupedBackground))
            .navigationTitle("热水洗澡").navigationBarTitleDisplayMode(.inline)
    }
    private var waterCard: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top,spacing:14) {
                Image(systemName:water.problem ? "exclamationmark.circle" : water.stage == .settled ? "checkmark.circle" : "drop")
                    .font(.title2).foregroundStyle(water.problem ? Color.orange : accent)
                    .frame(width:44,height:44).background(accent.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
                VStack(alignment:.leading,spacing:6) {
                    Text(water.busy ? "正在处理" : water.problem ? "本次未完成" : water.stage == .settled ? "上次已结算" : water.stage?.mayClose == true ? "热水已授权" : "准备洗澡")
                        .font(.headline)
                    Text(water.status).font(.subheadline).foregroundStyle(water.problem ? Color.orange : Color.secondary)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("waterStatus")
                }
                if water.busy { Spacer(minLength:0); ProgressView() }
            }
            VStack(spacing:10) {
                Button { perform(start:true) } label: {
                    Label("开始洗澡",systemImage:"drop.fill").frame(maxWidth:.infinity,minHeight:52)
                }.buttonStyle(WaterButtonStyle(primary:!water.mayFinish,accent:accent))
                    .disabled(!water.mayStart).accessibilityIdentifier("startWater")
                Button { perform(start:false) } label: {
                    Label("结束结算",systemImage:"stop.circle").frame(maxWidth:.infinity,minHeight:52)
                }.buttonStyle(WaterButtonStyle(primary:water.mayFinish,accent:accent))
                    .disabled(!water.mayFinish).accessibilityIdentifier("finishWater")
            }
            if water.configured {
                DisclosureGroup("连接检查") {
                    Button { Task { await water.inspectBluetooth() } } label: {
                        Label("检查蓝牙（不启动用水）",systemImage:"antenna.radiowaves.left.and.right")
                            .frame(maxWidth:.infinity,minHeight:44)
                    }.disabled(water.busy).accessibilityIdentifier("inspectWaterBluetooth")
                }
            }
            if let date = water.lastEnded {
                if water.stage == .settled {
                    HStack {
                        Text("本次费用").foregroundStyle(.secondary)
                        Spacer()
                        if let cost = water.lastCost {
                            Text(cost,format:.currency(code:"CNY")).font(.title3.weight(.semibold)).monospacedDigit()
                                .accessibilityIdentifier("settlementCost")
                        } else {
                            Text(water.hasReceipt ? "金额未返回" : "旧版未保存金额").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children:.combine)
                }
                Text("上次结算 \(date.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.tertiary)
            }
        }.padding(20).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:24))
    }
    private func perform(start:Bool) { Task { try? await water.run(start:start) } }
}

struct WaterButtonStyle: ButtonStyle {
    let primary: Bool
    let accent: Color
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .foregroundStyle(enabled ? (primary ? Color.white : accent) : Color.secondary)
            .background(enabled ? (primary ? accent : accent.opacity(0.08)) : Color(uiColor:.tertiarySystemFill),in:RoundedRectangle(cornerRadius:16))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:configuration.isPressed)
    }
}

private enum ConfigImport { case water, campus, laundry }
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var water: WaterModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    @State private var importing = false
    @State private var importKind = ConfigImport.campus
    private var version: String { (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—") + " · 内测" }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { QuickSetupView() } label: { Label("快速设置",systemImage:"checklist") }
                        .accessibilityIdentifier("quickSetupEntry")
                }
                Section {
                    NavigationLink { CampusOnboardingView() } label: {
                        Label("校园登录与宿舍",systemImage:"person.crop.circle")
                    }.accessibilityIdentifier("campusOnboardingEntry")
                    LabeledContent("宿舍",value:campus.room)
                    Button {
                        importKind = .campus; importing = true
                    } label: { LabeledContent("校园卡配置",value:campus.configured ? "已配置 · 更换" : "导入") }
                        .disabled(campus.loading)
                    Button { Task { await campus.refresh(force:true) } } label: {
                        Label(campus.loading ? "正在更新…" : "更新余额",systemImage:"arrow.clockwise")
                    }.disabled(!campus.configured || campus.loading)
                    if let issue = campus.issue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("校园卡与宿舍") } footer: {
                    Text("配置保存在本机钥匙串。查询失败保留上次余额，并显示查询状态。")
                }
                Section {
                    Button {
                        importKind = .water; importing = true
                    } label: { LabeledContent("热水配置",value:water.configured ? "已配置 · 更换" : "导入") }
                        .disabled(!water.mayImport)
                    Text(water.stage?.label ?? "暂无用水记录").font(.subheadline).foregroundStyle(.secondary)
                } header: { Text("热水") } footer: { Text("有未结算记录时不能更换热水配置。") }
                Section {
                    NavigationLink { WasherSetupView() } label: {
                        Label("常用洗衣机",systemImage:"qrcode.viewfinder")
                    }.accessibilityIdentifier("washerSetupEntry")
                    Button { importKind = .laundry; importing = true } label: {
                        LabeledContent("U净配置",value:laundry.configured ? "已配置 · 更换" : "导入")
                    }.disabled(!laundry.mayImport)
                    if let issue = laundry.issue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("洗衣机") } footer: {
                    Text("个人登录凭据保存在本机钥匙串。有待核对订单时不能更换配置。")
                }
                Section("快捷指令") {
                    Text("在快捷指令 App 搜索“校日常”，添加“开始洗澡”或“结束结算”。可放到主屏幕，或绑定操作按钮。")
                    Text("使用时保持手机解锁并靠近水控。首次需要允许蓝牙和网络访问。")
                }
                Section("未确认的操作") {
                    Text("超时后不要重复提交。先确认现场停水，再通过校园官方入口核对账单；App 会保留记录，不会自动重发。")
                    Text("本版本尚未提供不确定交易的自动恢复，请勿卸载 App 清记录。")
                }
                Section { LabeledContent("版本",value:version) }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
                .fileImporter(isPresented:$importing,allowedContentTypes:[.json,.data]) { result in
                    do {
                        let url = try result.get()
                        if importKind == .water { try water.importConfig(url) }
                        else if importKind == .campus { try campus.importConfig(url); Task { await campus.refresh(force:true) } }
                        else { try laundry.importConfig(url); Task { await laundry.refresh(force:true) } }
                    } catch {
                        if importKind == .water { water.show(error) }
                        else if importKind == .campus { campus.importFailed(error) }
                        else { laundry.importFailed() }
                    }
                }
        }
    }
}
