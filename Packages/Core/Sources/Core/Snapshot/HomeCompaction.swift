import Foundation

/// How far 清爽 home compresses itself on a short screen so it never scrolls below the
/// accessibility sizes. Each step keeps what the one before it did and adds one change; the
/// page takes the first step whose sections fit (`choose`), and 「最近」 then gets whatever
/// space is left (`RecentCardFit`).
public enum HomeCompaction: Int, Sendable, CaseIterable, Comparable {
    /// Everything as designed: room line, large title, cards at their full padding.
    case full = 0
    /// The room line 「周二 · 3 栋 108」 is hidden (the dorm is on the 热水 tile too).
    case noRoomLine = 1
    /// The title is the small one in the bar instead of the large one over the page.
    case inlineTitle = 2
    /// The tiles' padding and spacing and the balance card's header gap are tightened.
    case tightCards = 3
    /// 「继续设置」 drops its small line and keeps its title and chevron (VoiceOver still reads both).
    case setupTitleOnly = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var hidesRoomLine: Bool { self >= .noRoomLine }
    public var usesInlineTitle: Bool { self >= .inlineTitle }
    public var tightensCards: Bool { self >= .tightCards }
    public var shortensSetup: Bool { self >= .setupTitleOnly }

    /// Home's sections over 「最近」, each measured at the card's width at the current text size.
    public struct Sections: Sendable, Equatable {
        /// The large title over the page, under the bar.
        public var title: Double
        /// The room line.
        public var roomLine: Double
        /// 电量和校园卡, as designed and tightened.
        public var balance: Double
        public var balanceTight: Double
        /// 继续设置, and with its title only; 0 when it isn't shown.
        public var setup: Double
        public var setupShort: Double
        /// The 热水 and 洗衣 tiles, as designed and tightened.
        public var tiles: Double
        public var tilesTight: Double

        public init(title: Double, roomLine: Double, balance: Double, balanceTight: Double, setup: Double, setupShort: Double,
                    tiles: Double, tilesTight: Double) {
            self.title = title; self.roomLine = roomLine; self.balance = balance; self.balanceTight = balanceTight
            self.setup = setup; self.setupShort = setupShort; self.tiles = tiles; self.tilesTight = tilesTight
        }
    }

    /// The height the page takes at this step: the large title (until the inline one replaces
    /// it), then the page's padding above and below the sections and `gap` between each two.
    public func contentHeight(_ sections: Sections, pagePadding: Double, gap: Double) -> Double {
        var heights = [tightensCards ? sections.balanceTight : sections.balance,
                       tightensCards ? sections.tilesTight : sections.tiles]
        if !hidesRoomLine { heights.append(sections.roomLine) }
        if sections.setup > 0 { heights.append(shortensSetup ? sections.setupShort : sections.setup) }
        let title = usesInlineTitle ? 0 : sections.title
        return title + 2 * pagePadding + heights.reduce(0, +) + gap * Double(heights.count - 1)
    }

    /// The first step whose page fits in `viewport`, the height between the bars. At
    /// accessibility sizes home scrolls anyway: as designed. Nothing fits: the last step, the
    /// shortest page. Measured heights are fractions of a point: half a point over still fits.
    public static func choose(viewport: Double, sections: Sections, pagePadding: Double, gap: Double,
                              accessibilitySize: Bool) -> HomeCompaction {
        guard !accessibilitySize, viewport > 0 else { return .full }
        // Without 继续设置 the last step changes nothing: the one before it.
        let steps = sections.setup > 0 ? allCases : allCases.filter { !$0.shortensSetup }
        return steps.first { $0.contentHeight(sections, pagePadding: pagePadding, gap: gap) <= viewport + 0.5 } ?? steps[steps.count - 1]
    }
}
