//
//  TermStartSheet.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// 开学日: the day 「本学期」 counts from, on a date wheel over the days this term takes (the
/// model's `termStartRange`, through today). 完成 keeps it and closes; 「用回 9月1日」 (only once
/// it was changed) goes back to the default. Nothing is said after: the stats just count from
/// the new day.
struct TermStartSheet: View {
    struct Term: Equatable {
        /// The day this term counts from now.
        var start: Date
        /// Its default (3月1日 / 9月1日).
        var defaultStart: Date
        /// `start` was set by hand.
        var custom: Bool
        /// The days it can be set to (`CardRecordsModel.termStartRange`): every one counts.
        var range: ClosedRange<Date>
    }

    let term: Term
    /// The records' calendar: the wheel shows its days and a pick is that day's start in it.
    let calendar: Calendar
    var now = Date()
    /// The day picked, or nil to go back to the default.
    let onDone: (Date?) -> Void

    @State private var picked: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    init(term: Term, calendar: Calendar, now: Date = Date(), onDone: @escaping (Date?) -> Void) {
        self.term = term; self.calendar = calendar; self.now = now; self.onDone = onDone
        _picked = State(initialValue:term.start)
    }

    private var text: SpendStatsText { SpendStatsText(theme:theme, calendar:calendar) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:0) {
                    Text(text.termPickerTitle)
                        .scaledFont(15, .medium, relativeTo:.subheadline)
                        .foregroundStyle(Theme.ink)
                    DatePicker(text.termPickerTitle, selection:$picked, in:term.range, displayedComponents:.date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.timeZone, calendar.timeZone)
                        .environment(\.calendar, calendar)
                        .frame(maxWidth:.infinity)
                        .accessibilityIdentifier("termStartPicker")
                    Text(text.termFootnote)
                        .scaledFont(13, relativeTo:.footnote)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                    if term.custom {
                        Button {
                            onDone(nil)
                            dismiss()
                        } label: {
                            Text(text.termRestore(term.defaultStart))
                                .scaledFont(15, relativeTo:.subheadline)
                                .foregroundStyle(Theme.accentText)
                                .frame(minHeight:44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .padding(.top,8)
                        .accessibilityIdentifier("termStartRestore")
                    }
                }
                .padding(.horizontal,theme == .clear ? 20 : 24)
                .padding(.top,8).padding(.bottom,24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background {
                if theme == .clear { NativeTheme.background.ignoresSafeArea() } else { Theme.bg.ignoresSafeArea() }
            }
            .navigationTitle(text.termSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement:.confirmationAction) {
                    Button {
                        onDone(calendar.startOfDay(for:picked))
                        // Closes either way: a day the model refuses (the term moved on past
                        // midnight since the sheet opened) leaves the setting as it was.
                        dismiss()
                    } label: {
                        Text("完成").fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("termStartDone")
                }
            }
        }
        .tint(Theme.accentText)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
