import SwiftUI
import Core

/// 订单 tab root (「最近订单」): the recent laundry order and showers on top, then the card's
/// records with the app's own showers and laundry orders. The root pops this tab to its root when the signed-in person changes; the
/// list then starts again for them (`campus.personChanges`). DEBUG demos put their pages in
/// `navigator.recordsDemo`.
struct ClearRecordsTab: View {
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(ClearNavigator.self) private var navigator

    var body: some View {
        let data = shown
        let orders = ClearRecentOrders(data:data, laundry:laundryFacts)
        Group {
            if data.signedIn {
                // A new list (and records model) for each person and each graph: a sample's
                // never takes over the live list, nor the live one a sample's.
                ClearRecordsList(orders:orders, app:app(data), source:source)
                    .id(ListIdentity(services:campus.services.id, person:campus.personChanges))
            } else {
                ClearRecordsSignedOut(orders:orders)
            }
        }
        .navigationTitle(ClearRecentOrders.title)
        .navigationBarTitleDisplayMode(.large)
    }

    private var shown: HomeData {
        let data = navigator.data(campus:campus, shower:shower, laundry:laundry)
        if let demo = navigator.recordsDemo { return demo.shown(data) }
        return data
    }

    /// The live order, or a demo's (none for demos without one: the live model's isn't theirs).
    private var laundryFacts: LaundryFacts {
        if let demo = navigator.recordsDemo { return demo.laundryFacts() }
        if navigator.demo != nil { return LaundryFacts() }
        return LaundryFacts(model:laundry)
    }

    private func app(_ data: HomeData) -> [AppActivity] {
        if let demo = navigator.recordsDemo { return demo.app() }
        return data.recentActivities
    }

    private var source: CardRecordsSource {
        if let demo = navigator.recordsDemo { return demo.source }
        return .school(campus)
    }

    private struct ListIdentity: Hashable { let services: UUID; let person: Int }
}
