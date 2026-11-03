import SwiftUI
import Core

/// Home's recent rows in one card. The app's own showers and orders open their page; card
/// records are plain rows.
struct ClearRecentsCard: View {
    let items: [RecentItem]
    let open: (RecentItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing:0) {
            ForEach(Array(items.enumerated()), id:\.element.id) { index, item in
                Group {
                    if item.source == .app {
                        Button { open(item) } label: { ClearRecentRow(item:item, separator:index > 0) }
                            .buttonStyle(RowPressStyle())
                            .accessibilityAddTraits(.isButton)
                    } else {
                        ClearRecentRow(item:item, separator:index > 0)
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge:.top).combined(with:.opacity))
            }
        }
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
        .clipShape(RoundedRectangle(cornerRadius:16, style:.continuous))
        .animation(Theme.spring, value:items.map(\.id))
    }
}
