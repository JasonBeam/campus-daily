//
//  CardRecordsStats.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/24.
//

import SwiftUI
import Core

/// The spending stats over the card's records, on 暖橙's 校园卡记录 and 清爽's 订单: the records
/// model's (span kept, read back as far as the span needs).
struct CardRecordsStats: View {
    @ObservedObject var model: CardRecordsModel

    var body: some View {
        live(pinned:nil)
    }

    private func live(pinned: String?) -> some View {
        SpendStatsView(phase:phase, span:$model.statsSpan,
                       term:TermStartSheet.Term(start:model.termStart, defaultStart:model.defaultTermStart,
                                                custom:model.termStartIsCustom),
                       setTermStart:{ day in
                           if let day { model.setTermStart(day) } else { model.resetTermStart() }
                       },
                       pinned:pinned)
    }

    private var phase: SpendStatsView.Phase {
        if model.statsFailed { return .failed }
        if let stats = model.stats, !model.statsLoading { return .loaded(stats) }
        return .loading
    }
}
