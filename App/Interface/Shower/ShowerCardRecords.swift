//
//  ShowerCardRecords.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import SwiftUI
import Core

/// What 暖橙's hot-water pages may open and read of the campus card: 校园卡记录, where the
/// school's charge for a shower shows (about an hour later), and home's recent card records to
/// show a kept or stopped shower's charge. Home sets it (`HomeView.showerCardRecords`); the
/// default opens and shows nothing.
struct ShowerCardRecords: Sendable {
    /// 校园卡记录's contents (as home opens it).
    struct Page: Sendable {
        let app: [AppActivity]
        let source: CardRecordsSource
    }

    /// Nil while signed out of the school: 校园卡记录 can't open then, so no link shows.
    var page: Page?
    /// From the shower page, a cover over home: closes it and shows 校园卡记录 on home.
    var openFromCover: (@MainActor @Sendable () -> Void)?
    /// Home's last read of the card's recent records (nil while signed out or unread).
    var records: [CardRecord]?
    /// The calendar `records` are written in (`HomeData.calendar`).
    var calendar = SchoolCalendar.shanghai

    /// The card's charge for the shower started at `started`, when exactly one matched.
    func charge(started: Date?) -> Money? { ShowerCardCharge.amount(started:started, records:records, calendar:calendar) }
}

private struct ShowerCardRecordsKey: EnvironmentKey {
    static let defaultValue = ShowerCardRecords()
}

extension EnvironmentValues {
    var showerCardRecords: ShowerCardRecords {
        get { self[ShowerCardRecordsKey.self] }
        set { self[ShowerCardRecordsKey.self] = newValue }
    }
}

/// 「看校园卡记录 ›」: a small text link under a hot-water line, drawn as home's 「全部 ›」 at 15 pt.
/// It goes `gap` under its line, left-aligned at its own width; its text is at the top of a
/// frame at least 44 pt tall, so the space to tap reaches down, never up into the line.
struct ShowerCardRecordsLink: View {
    static let style = AccentChevronLabel.Style(size:15, relativeTo:.subheadline)
    /// From the line above to the link.
    static let gap: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action:action) {
            AccentChevronLabel(text:ShowerPageText.cardRecordsLink, style:Self.style)
                .frame(minHeight:44, alignment:.top)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(ShowerPageText.cardRecordsLink)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("showerCardRecordsLink")
    }
}

extension View {
    /// Pushes 校园卡记录 on this page's stack while `isPresented`.
    func showerCardRecordsDestination(isPresented: Binding<Bool>) -> some View {
        modifier(ShowerCardRecordsDestination(isPresented:isPresented))
    }
}

private struct ShowerCardRecordsDestination: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.showerCardRecords) private var records

    func body(content: Content) -> some View {
        content.navigationDestination(isPresented:$isPresented) {
            if let page = records.page {
                CardRecordsView(app:page.app, source:page.source).navOpen(.cardRecords, from:.homeButton)
            }
        }
    }
}
