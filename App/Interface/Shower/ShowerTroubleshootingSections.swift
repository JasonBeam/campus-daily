import SwiftUI
import Core

/// 高级 → 「连接检查」 and 「热水排查」: read-only Bluetooth check of the dorm controller and the
/// session review. Shown inline in AdvancedSettingsView's list.
struct ShowerTroubleshootingSections: View {
    /// DEBUG demo data from the settings sheet; nil = live model. Keeps 「热水」 here in step with the main page.
    var preview: HomeData? = nil
    @EnvironmentObject private var water: ShowerModel
    /// Same source as the main page's 「热水」 row: a dorm controller is bound (HomeData.shower != .unconfigured).
    private var waterConfigured: Bool { preview.map { $0.shower != .unconfigured } ?? water.configured }
    /// 检查水控状态 only means something while a session may be running.
    private var mayReview: Bool { preview.map { $0.shower.showering != nil } ?? water.mayReview }
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
            } header: { Text("热水排查") } footer: {
                Text("只看状态，不会开水，也不会结算。")
            }.listRowBackground(Theme.group)
        }
    }
}
