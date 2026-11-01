import SwiftUI
import Core

/// 高级 → 「连接检查」 and 「热水排查」: read-only Bluetooth check of the dorm controller, session
/// review and the diagnostics export. Shown inline in AdvancedSettingsView's list.
/// The export's share sheet and alert are attached by the list owner with `showerDiagnosticsExport`,
/// not here: these sections become lazily loaded list rows, and a presentation hung on a row can be
/// lost when the row is recycled.
struct ShowerTroubleshootingSections: View {
    /// DEBUG demo data from the settings sheet; nil = live model. Keeps 「热水」 here in step with the main page.
    var preview: HomeData? = nil
    @EnvironmentObject private var water: ShowerModel
    /// Same source as the main page's 「热水」 row: a dorm controller is bound (HomeData.shower != .unconfigured).
    private var waterConfigured: Bool { preview.map { $0.shower != .unconfigured } ?? water.configured }
    /// 检查水控状态 only means something while a session may be running.
    private var mayReview: Bool { preview.map { $0.shower.showering != nil } ?? water.mayFinish }
    @Binding var export: ShowerDiagnosticsExport
    var body: some View {
        Group {
            Section {
                if waterConfigured {
                    Button { if preview == nil { Task { await water.inspectBluetooth() } } } label: {
                        Label(water.inspecting ? "正在核对…" : (water.inspectionFoundBusy ? "再试一次" : "核对宿舍的水控"), systemImage:"antenna.radiowaves.left.and.right")
                    }.disabled(preview == nil && !water.mayImport).accessibilityIdentifier("inspectWaterBluetooth")
                    if let message = water.inspectionStatus {
                        Text(message).font(.subheadline).foregroundStyle(Theme.ink2).accessibilityIdentifier("waterInspectionStatus")
                    }
                    if let device = water.verifiedDevice {
                        LabeledContent("水控名称", value:device.name)
                        LabeledContent("水控编号", value:device.machineID).accessibilityIdentifier("verifiedWaterMachine")
                        if let rssi = device.rssi { LabeledContent("本次信号", value:"\(rssi) dBm") }
                        VStack(alignment:.leading, spacing:4) {
                            Text("水控标识 " + String(device.id.prefix(8)) + "…")
                            Text("发现 \(device.nearbyCount) 台同名水控，已按宿舍水控编号匹配。")
                            Text("核对于 " + device.verifiedAt.formatted(date:.omitted, time:.standard))
                        }.font(.caption).foregroundStyle(Theme.ink2)
                    }
                } else {
                    Text("导入热水配置后可以检查").foregroundStyle(Theme.ink2)
                }
            } header: { Text("连接检查") } footer: {
                Text("只读水控编号，不会开水。读完就断开，洗澡时再连。")
            }.listRowBackground(Theme.group)
            Section {
                Button { if preview == nil { Task { await water.reviewCurrentSession() } } } label: { ChevronRow(title:"检查水控状态") }
                    .disabled(!mayReview).accessibilityIdentifier("reviewWaterSession")
                Button {
                    do { export.url = try water.exportDiagnostics(); export.sharing = true }
                    catch { export.failed = true }
                } label: { ChevronRow(title:"导出热水诊断") }.accessibilityIdentifier("exportWaterDiagnostics")
            } header: { Text("热水排查") } footer: {
                VStack(alignment:.leading, spacing:6) {
                    Text("只看状态，不会开水，也不会结算。")
                    Text("诊断文件里有版本、操作时间和水控的回应，没有账号、密钥和水控编号。只记这次更新以后的操作。")
                }
            }.listRowBackground(Theme.group)
        }
    }
}

/// Presentation state of 「导出热水诊断」, owned by the view that owns the List.
struct ShowerDiagnosticsExport {
    var url: URL?
    var sharing = false
    var failed = false
}

extension View {
    /// The share sheet (a file was written) and the 「还没有诊断记录」 alert for ShowerTroubleshootingSections.
    /// Attach to the List itself, not to anything inside it.
    func showerDiagnosticsExport(_ export: Binding<ShowerDiagnosticsExport>) -> some View {
        sheet(isPresented:export.sharing) {
            if let url = export.wrappedValue.url { ShowerDiagnosticShare(url:url) }
        }
        .alert("还没有诊断记录，洗一次澡后再来导出。", isPresented:export.failed) { Button("好", role:.cancel) {} }
    }
}
