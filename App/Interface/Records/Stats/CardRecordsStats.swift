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
            SpendStatsView(phase:demo.phase(demoSpan), span:$demoSpan,
                           term:TermStartSheet.Term(start:SpendStatsDemo.termStart(), defaultStart:SpendStatsDemo.termStart(), custom:false,
                                                    range:TermStart.pickerRange(today:Date(), calendar:SchoolCalendar.shanghai)),
                           calendar:SchoolCalendar.shanghai)
        } else if let demo {
            // The sample records' own stats, on the demo's span (and its biggest bar for `day`).
            live(pinned:demo == .day ? model.stats?.bars.max { $0.spent < $1.spent }?.id : nil)
                .task {
                    try? await Task.sleep(for:.milliseconds(300))
                    model.statsSpan = demo.span
                    model.countOnly(demo.categories)
                    if demo == .refreshFailed { model.showDemoRefreshFailed() }
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
                       stale:model.refreshFailed, calendar:model.calendar)
    }

    private var phase: SpendStatsView.Phase {
        if model.statsFailed { return .failed }
        if let stats = model.stats, !model.statsLoading { return .loaded(stats) }
        return .loading
    }
}
