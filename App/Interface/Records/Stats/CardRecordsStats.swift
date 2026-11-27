//
//  CardRecordsStats.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// The spending stats over the card's records, on 暖橙's 校园卡记录 and 清爽's 订单: the records
/// model's (span kept, read back as far as the span needs), or in DEBUG a `SpendStatsDemo`'s.
struct CardRecordsStats: View {
    @ObservedObject var model: CardRecordsModel
    #if DEBUG
    private let demo = SpendStatsDemo.current
    @State private var demoSpan = SpendStatsDemo.current?.span ?? .week
    #endif

    var body: some View {
        #if DEBUG
        if let demo, demo.madeUp {
            let demoNow = Date()
            let demoStaleDay = demo == .refreshFailedOld
                ? SchoolCalendar.shanghai.date(byAdding:.day, value:-2, to:SchoolCalendar.shanghai.startOfDay(for:demoNow))
                : nil
            SpendStatsView(phase:demo.phase(demoSpan, now:demoNow), span:$demoSpan,
                           term:TermStartSheet.Term(start:SpendStatsDemo.termStart(now:demoNow), defaultStart:SpendStatsDemo.termStart(now:demoNow), custom:false,
                                                    range:TermStart.pickerRange(today:demoNow, calendar:SchoolCalendar.shanghai)),
                           stale:demo == .refreshFailedOld, staleSavedAt:demoStaleDay, staleToday:demoStaleDay,
                           now:demoNow, calendar:SchoolCalendar.shanghai)
        } else if let demo {
            // The sample records' own stats, on the demo's span (and its biggest bar for `day`).
            live(pinned:demo == .day ? model.stats?.bars.max { $0.spent < $1.spent }?.id : nil)
                .task {
                    try? await Task.sleep(for:.milliseconds(300))
                    model.statsSpan = demo.span
                    model.countOnly(demo.categories)
                    if demo == .refreshFailed {
                        let cal = model.calendar
                        let parts = cal.dateComponents([.year, .month, .day], from:model.currentNow)
                        let todayAt0830 = cal.date(from:DateComponents(year:parts.year, month:parts.month, day:parts.day, hour:8, minute:30))
                        model.showDemoRefreshFailed(savedAt:todayAt0830, cachedToday:cal.startOfDay(for:model.currentNow))
                    }
                }
        } else {
            live(pinned:nil)
        }
        #else
        live(pinned:nil)
        #endif
    }

    private func live(pinned: String?) -> some View {
        SpendStatsView(phase:phase, span:$model.statsSpan,
                       term:TermStartSheet.Term(start:model.termStart, defaultStart:model.defaultTermStart,
                                                custom:model.termStartIsCustom, range:model.termStartRange),
                       setTermStart:{ day in
                           if let day { model.setTermStart(day) } else { model.resetTermStart() }
                       },
                       pinned:pinned, comparing:model.comparisonLoading,
                       toggleCategory:{ model.toggleCategory($0) }, counted:model.includedCategories,
                       stale:model.refreshFailed, staleSavedAt:model.cachedSavedAt, staleToday:model.cachedToday,
                       now:model.currentNow, calendar:model.calendar)
    }

    private var phase: SpendStatsView.Phase {
        if model.statsFailed { return .failed }
        if let stats = model.stats, !model.statsLoading { return .loaded(stats) }
        return .loading
    }
}
