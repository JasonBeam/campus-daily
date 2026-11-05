import SwiftUI
import Core

/// 记录 tab root: the card's records with the app's own showers and laundry orders, and what is
/// still open on top. The root pops this tab to its root when the signed-in person changes; the
/// list then starts again for them (`campus.personChanges`). DEBUG demos put their pages in
/// `navigator.recordsDemo`.
struct ClearRecordsTab: View {
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(ClearNavigator.self) private var navigator

    var body: some View {
        let data = shown
        let open = ClearOpenItem.items(data)
        Group {
            if data.signedIn {
                // A new list (and records model) for each person and each graph: a sample's
                // never takes over the live list, nor the live one a sample's.
                ClearRecordsList(open:open, app:app(data), source:source)
                    .id(ListIdentity(services:campus.services.id, person:campus.personChanges))
            } else {
                ClearRecordsSignedOut(open:open)
            }
        }
        .navigationTitle("记录")
        .navigationBarTitleDisplayMode(.large)
    }

    private var shown: HomeData {
        let data = navigator.data(campus:campus, shower:shower, laundry:laundry)
        if let demo = navigator.recordsDemo { return demo.shown(data) }
        return data
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
