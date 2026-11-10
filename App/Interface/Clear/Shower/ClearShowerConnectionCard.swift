import SwiftUI
import Core

/// 2.6, 「连接检查与设备信息」: a read-only check of the dorm controller, folded into a card on
/// every face. 热水排查 stays in 设置 › 高级.
struct ClearShowerConnectionCard: View {
    @EnvironmentObject private var shower: ShowerModel
    @Environment(SampleMode.self) private var sample
    /// False on a DEBUG demo: the button does nothing there.
    let live: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(ClearShowerText.connection, isExpanded:$expanded) {
            VStack(alignment:.leading, spacing:12) {
                Button {
                    // Bluetooth: never in the sample.
                    if sample.isActive { sample.perform(.checkController) {}; return }
                    if live { Task { await shower.inspectBluetooth() } }
                } label: {
                    Label(shower.inspecting ? ClearShowerText.inspecting : ClearShowerText.inspect,
                          systemImage:"antenna.radiowaves.left.and.right")
                        .frame(maxWidth:.infinity, minHeight:44, alignment:.leading)
                }
                .disabled(live && !shower.mayImport)
                if let message = shower.inspectionStatus {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal:false, vertical:true)
                }
                if let device = shower.verifiedDevice {
                    VStack(alignment:.leading, spacing:12) {
                        Label(ClearShowerText.verified, systemImage:"checkmark.circle.fill")
                            .font(.headline).foregroundStyle(NativeTheme.tint)
                        LabeledContent(ClearShowerText.deviceName, value:device.name)
                        LabeledContent(ClearShowerText.machine, value:device.machineID)
                        Group {
                            Text(ClearShowerText.deviceID(String(device.id.prefix(8))))
                            Text(ClearShowerText.nearby(device.nearbyCount))
                            Text(ClearShowerText.verifiedAt(device.verifiedAt.formatted(date:.omitted, time:.standard)))
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Text(ClearShowerText.disconnected).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                }
                Text(ClearShowerText.readOnly)
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
