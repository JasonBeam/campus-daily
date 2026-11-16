import SwiftUI
import Core

/// 暖橙's list of the showers a next use kept: one row each (start time, controller, why it was
/// kept) and what to do about them. Read-only: nothing here settles or deletes them.
struct ShowerRetainedList: View {
    let summary: ShowerRetainedSummary

    var body: some View {
        List {
            Section {
                ForEach(Array(summary.entries.enumerated()), id:\.offset) { _, entry in
                    Text(ShowerRetainedText.row(entry, reason:ShowerRetainedText.Warm.reason(entry.reason), time:Self.time))
                        .font(.subheadline)
                        .fixedSize(horizontal:false, vertical:true)
                        .padding(.vertical,4)
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

    static func time(_ date: Date) -> String { date.formatted(date:.abbreviated, time:.shortened) }
}
