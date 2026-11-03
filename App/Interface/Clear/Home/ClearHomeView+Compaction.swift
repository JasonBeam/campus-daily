import SwiftUI
import Core

extension ClearHomeView {
    /// The first step at which the page fits between the bars (`HomeCompaction.choose`). As
    /// designed until the sections have been measured at the card's width (a frame measured at
    /// no width would otherwise flash a compressed page).
    var compaction: HomeCompaction {
        let cardWidth = CGFloat(Self.fit.cardWidth(screen:Double(viewport.width)))
        guard cardWidth > 0, abs(sectionsWidth - cardWidth) < 0.5, sections.balance > 0, sections.tiles > 0 else { return .full }
        return HomeCompaction.choose(viewport:Double(viewport.height), sections:sections, pagePadding:Self.fit.pagePadding,
                                     gap:Self.fit.gapAbove, accessibilitySize:typeSize.isAccessibilitySize)
    }

    /// The large title, the room line, 电量和校园卡 and the tiles as designed and tightened, and
    /// 继续设置 with and without its small line, hidden at the card's width, for their heights.
    func sectionMeasure(_ data: HomeData) -> some View {
        VStack(spacing:0) {
            ClearHomeTitle().fixedSize(horizontal:false, vertical:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { sections.title = Double($0) }
            roomLine(data).fixedSize(horizontal:false, vertical:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { sections.roomLine = Double($0) }
            ClearBalanceCard(data:data).fixedSize(horizontal:false, vertical:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { sections.balance = Double($0) }
            ClearBalanceCard(data:data, tight:true).fixedSize(horizontal:false, vertical:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { sections.balanceTight = Double($0) }
            // In a stack of its own, so it measures 0 while it isn't shown.
            VStack(spacing:0) { setupCard(data) }.fixedSize(horizontal:false, vertical:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { sections.setup = Double($0) }
            VStack(spacing:0) { setupCard(data, titleOnly:true) }.fixedSize(horizontal:false, vertical:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { sections.setupShort = Double($0) }
            tiles(data, tight:false)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { sections.tiles = Double($0) }
            tiles(data, tight:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { sections.tilesTight = Double($0) }
        }
        .frame(width:CGFloat(Self.fit.cardWidth(screen:Double(viewport.width))))
        .fixedSize(horizontal:false, vertical:true)
        .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { sectionsWidth = $0 }
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
