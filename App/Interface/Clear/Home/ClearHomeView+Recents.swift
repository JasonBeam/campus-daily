import SwiftUI
import Core

extension ClearHomeView {
    /// The whole rows that fit under the tiles, the header and the page's bottom padding, measured
    /// at the card's width; none, and no header or card, when not one does.
    func recentCount(_ items: [RecentItem]) -> Int {
        Self.fit.count(viewport:Double(viewport.height), above:Double(tilesBottom), header:Double(recentsHeaderHeight),
                       rowHeights:items.map { Double(recentHeights[$0.id] ?? 0) },
                       accessibilitySize:typeSize.isAccessibilitySize)
    }

    @ViewBuilder func recents(_ data: HomeData) -> some View {
        let items = data.recents
        let count = recentCount(items)
        if count > 0 {
            VStack(alignment:.leading, spacing:CGFloat(Self.fit.headerGap)) {
                ClearRecentsHeader(all:data.signedIn) { navigator.select(.records) }
                ClearRecentsCard(items:Array(items.prefix(count))) { item in
                    navigator.push(item.kind == .laundry ? .laundry : .shower, from:.recents)
                }
            }
        }
    }

    /// The header and every row as they would be drawn, hidden, at the card's width (the page's
    /// column, not the screen's), for their heights.
    func recentMeasure(_ data: HomeData) -> some View {
        let items = data.recents
        return VStack(spacing:0) {
            ClearRecentsHeader(all:data.signedIn) {}
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { recentsHeaderHeight = $0 }
            ForEach(Array(items.enumerated()), id:\.element.id) { index, item in
                ClearRecentRow(item:item, separator:index > 0)
                    .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { recentHeights[item.id] = $0 }
            }
        }
        .frame(width:CGFloat(Self.fit.cardWidth(screen:Double(viewport.width))))
        .fixedSize(horizontal:false, vertical:true)
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
