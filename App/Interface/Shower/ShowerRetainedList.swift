import SwiftUI
import Core

/// 暖橙's list of the showers a next use kept: two lines each, newest first (start time, then another controller · why it was
/// kept) and what to do about them. Read-only: nothing here settles or deletes them.
struct ShowerRetainedList: View {
    let summary: ShowerRetainedSummary

    var body: some View {
        List {
            Section {
                ForEach(Array(ShowerRetainedText.lines(summary, reason:ShowerRetainedText.Warm.reason).enumerated()), id:\.offset) { _, line in
                    VStack(alignment:.leading, spacing:4) {
                        Text(line.title).font(.body).foregroundStyle(Theme.ink)
                        if let detail = line.detail {
                            Text(detail).font(.subheadline).foregroundStyle(Theme.ink2)
                        }
                    }
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.vertical,4)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(line.spoken)
                }
            } footer: {
                Text(ShowerRetainedText.Warm.footer)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(ShowerRetainedText.Warm.listTitle)
        .navigationBarTitleDisplayMode(.inline)
        .typesettingLanguage(Theme.typesetting)
        .accessibilityIdentifier("showerRetainedList")
        .navOpen(.showerRetained, from:.homeButton)
    }
}
