import SwiftUI
import Core

/// 3.1: the machine — symbol tile, 「3 号机 · 波轮洗衣机」 and its store, then its state and when
/// it was read.
struct ClearLaundryDeviceCard: View {
    let snapshot: WasherSnapshot
    let state: String
    /// Busy, offline, broken or disabled: the state in `notice`.
    let problem: Bool

    var body: some View {
        VStack(alignment:.leading, spacing:14) {
            HStack(alignment:.top, spacing:14) {
                Image(systemName:"washer")
                    .font(.title).foregroundStyle(Theme.accentText)
                    .frame(width:52, height:52)
                    .background(Theme.accent.opacity(0.08), in:RoundedRectangle(cornerRadius:16, style:.continuous))
                    .accessibilityHidden(true)
                VStack(alignment:.leading, spacing:6) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    if !snapshot.storeName.isEmpty {
                        Text(snapshot.storeName).font(.subheadline).foregroundStyle(Theme.ink2)
                    }
                }
                .fixedSize(horizontal:false, vertical:true)
            }
            HStack(alignment:.firstTextBaseline) {
                Label {
                    Text(state).font(.caption.weight(.medium))
                } icon: {
                    Image(systemName:"circle.fill").font(.system(size:7))
                }
                .foregroundStyle(problem ? Theme.notice : Theme.accentText)
                Spacer(minLength:8)
                Text(Theme.updated(snapshot.fetchedAt)).font(.caption).monospacedDigit().foregroundStyle(Theme.ink2)
            }
        }
        .padding(20)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
        .accessibilityElement(children:.combine)
    }

    private var title: String {
        let type = snapshot.info.typeName
        return LaundryFormat.machine(snapshot.deviceNo) + (type.isEmpty ? "" : " · " + type)
    }
}
