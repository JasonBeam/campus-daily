import SwiftUI
import Core

/// 2.6, 「连接检查与水控信息」: 高级's 连接检查 (read-only check of the dorm controller) folded
/// into a card, as on his detail page. 热水排查 stays in 设置 › 高级.
struct ClearShowerConnectionCard: View {
    @EnvironmentObject private var shower: ShowerModel
    @Environment(SampleMode.self) private var sample
    /// False on a DEBUG demo: the button does nothing there.
    let live: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("连接检查与水控信息", isExpanded:$expanded) {
            VStack(alignment:.leading, spacing:12) {
                Button {
                    // Bluetooth: never in the sample.
                    if sample.isActive { sample.perform(.checkController) {}; return }
                    if live { Task { await shower.inspectBluetooth() } }
                } label: {
                    Label(shower.inspecting ? "正在核对…" : (shower.inspectionFoundBusy ? "再试一次" : "核对宿舍的水控"),
                          systemImage:"antenna.radiowaves.left.and.right")
                        .frame(maxWidth:.infinity, minHeight:44, alignment:.leading)
                }
                .disabled(live && !shower.mayImport)
                if let message = shower.inspectionStatus {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal:false, vertical:true)
                }
                if let device = shower.verifiedDevice {
                    LabeledContent("水控名称", value:device.name)
                    LabeledContent("水控编号", value:device.machineID)
                    VStack(alignment:.leading, spacing:4) {
                        Text("水控标识 " + String(device.id.prefix(8)) + "…")
                        Text("发现 \(device.nearbyCount) 台同名水控，已按宿舍水控编号匹配。")
                        Text("核对于 " + device.verifiedAt.formatted(date:.omitted, time:.standard))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Text("只读水控编号，不会开水。读完就断开，洗澡时再连。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false, vertical:true)
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
        .tint(NativeTheme.tint)
        .padding(18)
        .background(NativeTheme.surface, in:RoundedRectangle(cornerRadius:16, style:.continuous))
    }
}
