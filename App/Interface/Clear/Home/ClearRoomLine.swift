import SwiftUI
import Core

/// 「周一 · 3 栋 108」 over the balances, with a small spinner while the school is read.
/// Signed out: the spinner alone.
struct ClearRoomLine: View {
    let dorm: String?
    let signedIn: Bool
    let refreshing: Bool

    var body: some View {
        HStack(alignment:.firstTextBaseline) {
            if signedIn {
                Text([SchoolCalendar.weekday(Date()), dorm].compactMap { $0 }.joined(separator:" · "))
                    .font(.subheadline).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength:8)
            if refreshing {
                ProgressView().controlSize(.small).accessibilityLabel("正在更新…")
            }
        }
    }
}
