//
//  HomeView+CardRecords.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import SwiftUI
import Core

extension HomeView {
    /// 校园卡记录 for the hot-water pages' 「看校园卡记录」 (as home's 「全部」 opens it) and the
    /// card's recent records for their 「校园卡已扣」: only while signed in to the school, never on
    /// the sample's pages.
    var showerCardRecords: ShowerCardRecords {
        let data = self.data
        guard data.signedIn, !sample.isActive else { return ShowerCardRecords() }
        // A DEBUG demo's link opens synthetic pages, never the school's.
        let page = ShowerCardRecords.Page(app:recordsDemo?.app() ?? data.recentActivities,
                                          source:recordsDemo?.source ?? (demo != nil ? RecordsDemo.list.source : .school(campus)))
        return ShowerCardRecords(page:page, openFromCover:{ openCardRecordsFromShowerPage() },
                                 activity:data.snapshot.activity.value, calendar:data.calendar)
    }

    /// The shower page is a cover: it goes down first, then 校园卡记录 is pushed over the pages
    /// under it.
    func openCardRecordsFromShowerPage() {
        shower.pageEvent(.closeTapped)
        destination.after(450) {
            open(path.last == .records ? path : path + [.records], from:.pageEvent)
        }
    }
}
