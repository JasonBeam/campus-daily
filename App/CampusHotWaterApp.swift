import SwiftUI
import UniformTypeIdentifiers
import WaterCore

@main struct CampusHotWaterApp: App {
    @StateObject private var water = WaterModel.shared
    @StateObject private var campus = CampusModel()
    @StateObject private var laundry = LaundryModel()
    var body: some Scene {
        WindowGroup {
            CampusRootView().environmentObject(water).environmentObject(campus).environmentObject(laundry)
                .task {
                    #if CAMPUS_ACCESS_DIAGNOSTICS
                    if ProcessInfo.processInfo.arguments.contains("--check-water-access") {
                        await AccessDiagnostics.run(campus:campus)
                        return
                    }
                    #endif
                    water.importDevelopmentConfigIfPresent()
                    campus.importDevelopmentConfigIfPresent()
                    laundry.importDevelopmentConfigIfPresent()
                    await water.migrateBundledDirectIfNeeded(campus:campus.onboardingLogin)
                    await laundry.recoverDevelopmentOrderIfPresent()
                    campus.matchPowerAutomatically()
                    await campus.refresh()
                    await laundry.refresh()
                }
                .onOpenURL { if $0.scheme != "campusdaily" { AlipayBridge.shared.handle($0); Task { await laundry.refreshOrder() } } }
        }
    }
}

struct WaterHome: View {
    @EnvironmentObject private var water: WaterModel
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var settings = false
    @State private var firstRun = false
    @AppStorage("didSeeQuickSetup") private var didSeeQuickSetup = false
    @ScaledMetric(relativeTo:.largeTitle) private var balanceSize: CGFloat = 34
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HStack(alignment:.firstTextBaseline) {
                        Text(campus.room).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("dormRoom")
                        Spacer()
                        if campus.loading { ProgressView().controlSize(.small).accessibilityLabel("更新余额") }
                    }
                    balances
                    if !campus.configured || !water.configured || !laundry.configured {
                        NavigationLink { QuickSetupView() } label: {
                            HStack(spacing:12) {
                                Image(systemName:"slider.horizontal.3").foregroundStyle(NativeTheme.tint)
                                VStack(alignment:.leading,spacing:5) {
                                    Text("继续完成设置").font(.subheadline.weight(.medium))
                                    Text("账号、宿舍和常用洗衣机").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary).padding(16).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain)
                    }
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.top,spacing:12) { waterTile.frame(minWidth:145); laundryTile.frame(minWidth:145) }
                        VStack(spacing:12) { waterTile; laundryTile }
                    }
                    if let record = laundry.checkout, record.stage != .completed {
                        NavigationLink { LaundryDetail() } label: {
                            HStack(spacing:13) {
                                Image(systemName:"clock.arrow.circlepath").foregroundStyle(NativeTheme.tint)
                                VStack(alignment:.leading,spacing:5) {
                                    Text("洗衣订单").font(.headline)
                                    Text(record.order?.label ?? "订单结果待核对").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary).padding(17).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain)
                    }
                    if let ended = water.lastEnded {
                        HStack(spacing:12) {
                            VStack(alignment:.leading,spacing:5) {
                                Text("上次热水 · 已结算").font(.subheadline)
                                Text(ended.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let cost = water.lastCost { Text(cost,format:.currency(code:"CNY")).font(.subheadline.weight(.medium)).monospacedDigit() }
                        }.padding(16).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                    }
                    Text("下拉刷新余额").font(.caption).foregroundStyle(.secondary).padding(.horizontal,4)
                }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
            }.background(NativeTheme.background)
                .navigationTitle("校园生活").navigationBarTitleDisplayMode(.large)
                .toolbar { ToolbarItem(placement:.topBarTrailing) {
                    Button { settings = true } label: { Image(systemName:"slider.horizontal.3").frame(width:44,height:44) }.accessibilityLabel("设置与个人配置")
                } }
                .refreshable { await campus.refresh(force:true); await laundry.refresh(force:true) }
                .sheet(isPresented:$settings) { SettingsView() }
                .sheet(isPresented:$firstRun,onDismiss:{ didSeeQuickSetup = true }) {
                    NavigationStack { QuickSetupView().toolbar {
                        ToolbarItem(placement:.confirmationAction) { Button("稍后设置") { firstRun = false } }
                    } }
                }
                .task { if !didSeeQuickSetup && !campus.configured && !water.configured && !laundry.configured { firstRun = true } }
                .onChange(of:phase) { _,value in if value == .active { Task { await campus.refresh(); await laundry.refresh(); await laundry.refreshOrder() } } }
                .onChange(of:water.stage) { old,value in if old != .settled, value == .settled { Task { await campus.refresh(force:true) } } }
        }.tint(NativeTheme.tint)
    }
    private var waterTile: some View {
        NavigationLink { WaterDetail() } label: {
            ServiceTile(title:"热水洗澡",symbol:"drop",status:water.busy ? "处理中" : water.problem ? "待核对" : !water.configured ? "待配置" : water.stage == .active ? "已授权" : water.stage?.mayClose == true ? "待核对" : "可连接",
                detail:campus.room,color:NativeTheme.tint)
        }.buttonStyle(.plain).accessibilityIdentifier("waterEntry")
    }
    private var laundryTile: some View {
        NavigationLink { LaundryDetail() } label: {
            ServiceTile(title:"洗衣机",symbol:"washer",status:laundry.deviceStateText,
                detail:laundry.snapshot.map { "常用 · \($0.deviceNo)号" } ?? "登录与扫码绑定",color:NativeTheme.tint)
        }.buttonStyle(.plain).accessibilityIdentifier("laundryEntry")
    }
    private var balances: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("双余额").font(.headline)
                Spacer()
                NavigationLink { CampusPowerSetupView() } label: {
                    Text(campus.powerConfigured ? "电表设置" : "绑定电表").font(.caption).frame(minHeight:44)
                }
            }
            if typeSize.isAccessibilitySize {
                powerMetric; Divider(); cardMetric
            } else {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.top,spacing:16) { powerMetric.frame(minWidth:140); cardMetric.frame(minWidth:130) }
                    VStack(alignment:.leading,spacing:18) { powerMetric; Divider(); cardMetric }
                }
            }
            if let issue = campus.issue { Text(issue).font(.footnote).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            if let error = campus.snapshot?.powerError { Text("电费：" + error.rawValue).font(.footnote).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
        }.padding(.horizontal,16).padding(.bottom,16).padding(.top,6)
            .background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
    }
    private var powerMetric: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("宿舍电量").font(.subheadline).foregroundStyle(.secondary)
            metricValue(campus.snapshot?.electricity.map { decimal($0.remainingKWh) } ?? "—",unit:"度")
            VStack(alignment:.leading,spacing:6) {
                Text("电费 " + (campus.snapshot?.electricity.map { "¥" + decimal($0.balanceYuan) } ?? "未获取"))
                Text("昨日 " + (campus.snapshot?.electricity?.yesterdayKWh.map { decimal($0) + " 度" } ?? "未返回"))
            }.font(.caption).foregroundStyle(.secondary)
            if let stamp = campus.snapshot?.powerFetchedAt {
                Text((campus.snapshot?.powerIsStale() == true ? "上次 " : "查询 ") + stamp.formatted(date:.omitted,time:.shortened)).font(.caption2).foregroundStyle(.secondary)
            }
            NavigationLink { CampusRechargeView(kind:.power) } label: { Text("充电费 ↗").font(.subheadline).frame(minHeight:44) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var cardMetric: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("校园卡").font(.subheadline).foregroundStyle(.secondary)
            metricValue(campus.balanceText,unit:"元").accessibilityIdentifier("campusBalance")
            VStack(alignment:.leading,spacing:6) {
                Text("校园消费余额")
                Text(campus.freshness)
            }.font(.caption).foregroundStyle(.secondary)
            if let stamp = campus.snapshot?.balanceFetchedAt { Text("查询 " + stamp.formatted(date:.omitted,time:.shortened)).font(.caption2).foregroundStyle(.secondary) }
            NavigationLink { CampusRechargeView(kind:.card) } label: { Text("充校园卡 ↗").font(.subheadline).frame(minHeight:44) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func metricValue(_ value: String,unit: String) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:4) {
            Text(value).font(.system(size:balanceSize,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children:.combine)
    }
    private func decimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier:"zh_CN")
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return formatter.string(from:NSDecimalNumber(decimal:value)) ?? "—"
    }
}

struct WaterDetail: View {
    @EnvironmentObject private var water: WaterModel
    @EnvironmentObject private var campus: CampusModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack { Text("宿舍热水"); Spacer(); Text(campus.room) }.font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment:.leading,spacing:13) {
                    HStack(spacing:9) {
                        if water.busy { ProgressView().controlSize(.small) }
                        else { Circle().fill(water.problem ? Color.orange : NativeTheme.tint).frame(width:7,height:7).accessibilityHidden(true) }
                        Text(headline).font(.title2.bold()).accessibilityIdentifier("waterHeadline")
                    }
                    Text(water.inspecting ? "正在只读核对附近水控，不会出水。" : water.status).font(.subheadline).foregroundStyle(water.problem ? Color.orange : Color.secondary)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("waterStatus")
                }
                HStack {
                    Text("本次费用").foregroundStyle(.secondary)
                    Spacer()
                    if water.stage == .settled, let cost = water.lastCost {
                        Text(cost,format:.currency(code:"CNY")).font(.title2.weight(.semibold)).monospacedDigit().accessibilityIdentifier("settlementCost")
                    } else if water.stage == .settled {
                        Text(water.hasReceipt ? "金额未返回" : "旧记录未保存金额").font(.subheadline).foregroundStyle(.secondary)
                    } else { Text("结算后显示").font(.subheadline) }
                }.padding(18).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                if let ended = water.lastEnded {
                    VStack(alignment:.leading,spacing:14) {
                        Text("最近一次用水").font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            VStack(alignment:.leading,spacing:6) {
                                Text("已结算").font(.subheadline)
                                Text(ended.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let cost = water.lastCost { Text(cost,format:.currency(code:"CNY")).font(.subheadline).monospacedDigit() }
                        }
                    }.padding(18).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                }
                if !water.configured {
                    NavigationLink("设置校园账号与宿舍") { CampusOnboardingView() }.frame(minHeight:44)
                }
                if water.configured {
                    DisclosureGroup("连接检查与设备信息") {
                        Button { Task { await water.inspectBluetooth() } } label: {
                            Label(water.inspecting ? "正在核对…" : "扫描并核对本宿舍水控",systemImage:"antenna.radiowaves.left.and.right").frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                        }.disabled(!water.mayImport).accessibilityIdentifier("inspectWaterBluetooth")
                        if let message = water.inspectionStatus {
                            Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("waterInspectionStatus")
                        }
                        if let device = water.verifiedDevice {
                            VStack(alignment:.leading,spacing:12) {
                                Label("已识别的宿舍设备",systemImage:"checkmark.circle.fill").font(.headline).foregroundStyle(NativeTheme.tint)
                                LabeledContent("设备名称",value:device.name)
                                LabeledContent("水控编号",value:device.machineID).accessibilityIdentifier("verifiedWaterMachine")
                                if let rssi = device.rssi { LabeledContent("本次信号",value:"\(rssi) dBm") }
                                Text("设备标识 " + String(device.id.prefix(8)) + "…").font(.caption).foregroundStyle(.secondary)
                                Text("发现 \(device.nearbyCount) 台同名设备，已按宿舍水控编号匹配。").font(.caption).foregroundStyle(.secondary)
                                Text("核对于 " + device.verifiedAt.formatted(date:.omitted,time:.standard)).font(.caption).foregroundStyle(.secondary)
                                Text("核对后已断开；开始洗澡时再连接。").font(.footnote).foregroundStyle(.secondary)
                            }.font(.subheadline).padding(.vertical,10)
                        }
                        Text("只读取设备编号，不会出水。").font(.footnote).foregroundStyle(.secondary)
                    }.font(.subheadline).padding(18).background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:16))
                }
            }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(NativeTheme.background)
            .navigationTitle("热水洗澡").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {
                VStack(spacing:10) {
                    Button { perform(start:!closing) } label: {
                        HStack {
                            if water.busy { ProgressView().tint(.white).controlSize(.small) }
                            Text(water.busy ? "正在处理…" : closing ? "结束并结算" : "开始洗澡")
                            Spacer(); Image(systemName:closing ? "stop.circle" : "arrow.up.right")
                        }.padding(.horizontal,18).frame(minHeight:52)
                    }.buttonStyle(WaterButtonStyle(primary:true,accent:NativeTheme.tint))
                        .disabled(closing ? !water.mayFinish : !water.mayStart)
                        .accessibilityIdentifier(closing ? "finishWater" : "startWater")
                    Text(closing ? "结算完成前，请留在水控附近。" : "授权后，按水控上的出水键。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.horizontal,20).padding(.top,12).padding(.bottom,12).background(NativeTheme.background)
            }
            .sheet(isPresented:Binding(get:{ !water.deviceCandidates.isEmpty },set:{ if !$0 { water.cancelDeviceSelection() } })) {
                NavigationStack {
                    List {
                        Section {
                            Text("附近有多台同名水控，请靠近自己宿舍的设备后选择。信号强度仅供参考，连接后还会核对宿舍水控编号。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Section("选择水控") {
                            ForEach(water.deviceCandidates) { device in
                                Button { water.chooseDevice(device.id) } label: {
                                    HStack(spacing:12) {
                                        Image(systemName:"antenna.radiowaves.left.and.right")
                                        VStack(alignment:.leading,spacing:6) {
                                            Text(device.name).font(.headline)
                                            Text("设备标识 " + device.id).font(.caption).foregroundStyle(.secondary)
                                            if let rssi = device.rssi { Text("信号 \(rssi) dBm").font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }.frame(maxWidth:.infinity,minHeight:60,alignment:.leading)
                                }.accessibilityIdentifier("waterDevice-" + device.id)
                            }
                        }
                    }.navigationTitle("选择水控设备").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { water.cancelDeviceSelection() } } }
                }
            }
            .onChange(of:phase) { _,value in if value == .background { water.cancelDeviceSelection() } }
            .onDisappear { water.cancelDeviceSelection() }
    }
    private var closing: Bool { water.stage?.mayClose == true }
    private var headline: String {
        if water.inspecting { return "正在核对设备" }
        if water.busy { return "正在处理" }
        if water.problem { return "本次待核对" }
        if !water.configured { return "尚未配置热水" }
        if water.stage == .active { return "热水已授权" }
        if water.stage == .settled { return "结算完成" }
        if water.stage != nil { return "当前记录待核对" }
        return "准备洗澡"
    }
    private func perform(start:Bool) { Task { try? await water.run(start:start,allowDeviceSelection:true) } }
}

struct WaterButtonStyle: ButtonStyle {
    let primary: Bool
    let accent: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .foregroundStyle(primary ? Color.white : accent)
            .background(primary ? NativeTheme.action : NativeTheme.tint.opacity(0.10),in:RoundedRectangle(cornerRadius:12))
            .opacity(enabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
    }
}

private enum ConfigImport { case water, campus, laundry }
struct SettingsView: View {
    var showsDone = true
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
                    NavigationLink { QuickSetupView() } label: {
                        VStack(alignment:.leading,spacing:8) {
                            Text("首次配置").font(.caption).foregroundStyle(.secondary)
                            Text("账号与设备设置").font(.headline)
                            Text("跟着步骤登录、选宿舍、扫机器").font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical,10)
                    }.accessibilityIdentifier("quickSetupEntry")
                }
                Section("我的信息") {
                    NavigationLink { CampusOnboardingView() } label: {
                        LabeledContent("校园账号与宿舍",value:campus.configured ? campus.room : "去登录")
                    }.accessibilityIdentifier("campusOnboardingEntry")
                    NavigationLink { WasherSetupView() } label: {
                        LabeledContent("常用洗衣机",value:laundry.accountConnected ? "已登录 · \(laundry.savedMachines.count) 台" : "去设置")
                    }.accessibilityIdentifier("washerSetupEntry")
                    Button { Task { await campus.refresh(force:true) } } label: { Text(campus.loading ? "正在更新余额…" : "更新校园卡余额") }
                        .disabled(!campus.configured || campus.loading)
                }
                Section("快捷使用") {
                    Text("在快捷指令 App 搜索“校日常”，添加“开始洗澡”或“结束结算”，放到主屏幕。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("高级设置与故障排查") {
                        Text("通常无需导入文件。请优先使用上方账号与设备设置。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("导入校园卡配置") { importKind = .campus; importing = true }.disabled(campus.loading)
                        Button("导入热水配置") { importKind = .water; importing = true }.disabled(!water.mayImport)
                        Button("导入 U净配置") { importKind = .laundry; importing = true }.disabled(!laundry.mayImport)
                        Text("有未结算记录时请勿卸载或更换配置。操作未确认时，先核对现场及官方记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("版本",value:version).font(.footnote).foregroundStyle(.secondary)
                }
            }.scrollContentBackground(.hidden).background(NativeTheme.background).tint(NativeTheme.tint)
                .navigationTitle(showsDone ? "设置" : "设备与设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { if showsDone { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } } }
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
