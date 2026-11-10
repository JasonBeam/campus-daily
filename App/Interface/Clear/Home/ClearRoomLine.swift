import SwiftUI
import Core

/// 「3栋108」 over the balances, with a small spinner while the school is read.
struct ClearRoomLine: View {
    let room: String?
    let refreshing: Bool

    var body: some View {
        HStack(alignment:.firstTextBaseline) {
            if let room { Text(room).font(.subheadline).foregroundStyle(Theme.ink2) }
            Spacer(minLength:8)
            if refreshing {
                ProgressView().controlSize(.small).accessibilityLabel("更新余额")
            }
        }
    }
}
