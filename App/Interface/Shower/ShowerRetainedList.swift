import SwiftUI
import Core

/// 暖橙's list of the showers a next use kept: two lines each (a third, 「校园卡已扣 ¥x」, when the card's records show its charge), newest first (start time, then another controller · why it was
/// kept) and what to do about them, with a link to 校园卡记录 under that. Read-only: nothing here settles or deletes them.
struct ShowerRetainedList: View {
    let summary: ShowerRetainedSummary
    @Environment(\.showerCardRecords) private var cardRecords
    @State private var recordsOpen = false

    var body: some View {
        List {
            Section {
                ForEach(Array(ShowerRetainedText.lines(summary, reason:ShowerRetainedText.Warm.reason,
                                                       charge:{ cardRecords.charge(started:$0) }).enumerated()), id:\.offset) { _, line in
                    VStack(alignment:.leading, spacing:4) {
                        Text(line.title).font(.body).foregroundStyle(Theme.ink)
                        if let detail = line.detail {
                            Text(detail).font(.subheadline).foregroundStyle(Theme.ink2)
                        }
                        if let charge = line.charge {
                            Text(charge).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Theme.ink)
                        }
                    }
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.vertical,4)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(line.spoken)
                }
            } footer: {
                VStack(alignment:.leading, spacing:ShowerCardRecordsLink.gap) {
                    Text(ShowerRetainedText.Warm.footer)
                    if cardRecords.page != nil { ShowerCardRecordsLink { recordsOpen = true } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .showerCardRecordsDestination(isPresented:$recordsOpen)
        .navigationTitle(ShowerRetainedText.Warm.listTitle)
        .navigationBarTitleDisplayMode(.inline)
        .typesettingLanguage(Theme.typesetting)
        .accessibilityIdentifier("showerRetainedList")
        .navOpen(.showerRetained, from:.homeButton)
    }
}
