import SwiftUI
import Core

extension HomeView {
    /// 校园卡记录 for the hot-water pages' 「看校园卡记录」: as home's 「全部」 opens it, and only
    /// while signed in to the school (never on the sample's pages).
    var showerCardRecords: ShowerCardRecords {
        let data = self.data
        guard data.signedIn, !sample.isActive else { return ShowerCardRecords() }
        let page = ShowerCardRecords.Page(app:recordsDemo?.app() ?? data.recentActivities,
                                          source:recordsDemo?.source ?? .school(campus))
        return ShowerCardRecords(page:page, openFromCover:{ openCardRecordsFromShowerPage() })
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
