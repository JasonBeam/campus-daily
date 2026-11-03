import SwiftUI

/// A home tile (热水洗澡, 洗衣): symbol, title, detail, and a status line with ↗. The whole tile
/// is one button.
struct ClearServiceTile<Status: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var dimmed = false
    /// Short screens (`HomeCompaction.tightCards`): padding 14 instead of 18, 10 between the
    /// symbol, the title and the status instead of 16.
    var tight = false
    let action: () -> Void
    @ViewBuilder var status: Status

    var body: some View {
        Button(action:action) {
            VStack(alignment:.leading, spacing:tight ? 10 : 16) {
                Image(systemName:symbol).font(.title2).foregroundStyle(Theme.accentText).accessibilityHidden(true)
                VStack(alignment:.leading, spacing:6) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(detail).font(.caption).foregroundStyle(Theme.ink2).fixedSize(horizontal:false, vertical:true)
                }
                Spacer(minLength:0)
                HStack(alignment:.firstTextBaseline, spacing:6) {
                    // First claim on the width, before the spacer: the longest form that fits.
                    status.font(.caption).fixedSize(horizontal:false, vertical:true).layoutPriority(1)
                    Spacer(minLength:0)
                    Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(Theme.accentText).accessibilityHidden(true)
                }
            }
            .padding(tight ? 14 : 18)
            .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
            .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
            .contentShape(RoundedRectangle(cornerRadius:16, style:.continuous))
            .opacity(dimmed ? 0.5 : 1)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children:.combine)
    }
}
