import SwiftUI
import Core

/// The kept showers on 热水洗澡: one line with their count; a tap opens the 订单 tab, where each
/// is listed. Read-only: nothing here settles or deletes them.
struct ClearShowerRetainedLine: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action:open) {
            ClearLinkRow {
                Label {
                    Text(ShowerRetainedText.Clear.line(count:count))
                        .font(.subheadline).foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal:false, vertical:true)
                } icon: {
                    Image(systemName:"tray.full").foregroundStyle(Color.secondary)
                }
            }
            .padding(.vertical,14).padding(.horizontal,18)
            .frame(maxWidth:.infinity, minHeight:44, alignment:.leading)
            .background(NativeTheme.surface, in:RoundedRectangle(cornerRadius:16, style:.continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(ShowerRetainedText.Clear.spoken(count:count))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("showerRetainedLine")
    }
}
