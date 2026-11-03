import SwiftUI

/// 「最近」 over home's recent rows and, while signed in, 「全部 ›」 to the 记录 tab.
struct ClearRecentsHeader: View {
    let all: Bool
    let openAll: () -> Void

    var body: some View {
        HStack(alignment:.firstTextBaseline) {
            Text("最近").font(.subheadline).foregroundStyle(Theme.ink2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength:8)
            if all {
                Button("全部 ›", action:openAll)
                    .font(.subheadline).foregroundStyle(Theme.accentText)
                    .buttonStyle(.plain)
                    // 44 pt to tap without moving 「最近」.
                    .padding(.vertical,12).padding(.leading,8).contentShape(Rectangle()).padding(.vertical,-12)
                    .accessibilityLabel("全部")
                    .accessibilityIdentifier("allRecords")
            }
        }
        .padding(.horizontal,4)
    }
}
