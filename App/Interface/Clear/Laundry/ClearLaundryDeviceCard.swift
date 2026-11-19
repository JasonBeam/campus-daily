import SwiftUI
import Core

/// The machine: symbol tile, 「3号 · 波轮洗衣机」 and its store, then its state with how fresh the
/// read is, and when it was read.
struct ClearLaundryDeviceCard: View {
    let snapshot: WasherSnapshot
    let state: String
    let freshness: String

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
                Label(state, systemImage:"circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accentText)
                Spacer(minLength:8)
                Text(freshness).font(.caption).foregroundStyle(Theme.ink2)
            }
            Text(ClearLaundryCopy.queried(snapshot.fetchedAt)).font(.caption).monospacedDigit().foregroundStyle(Theme.ink2)
        }
        .padding(20)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
        .accessibilityElement(children:.combine)
    }

    private var title: String {
        let type = snapshot.info.typeName
        return "\(snapshot.deviceNo)号" + (type.isEmpty ? "" : " · " + type)
    }
}
