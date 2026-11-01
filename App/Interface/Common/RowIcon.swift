import SwiftUI

/// The grey line symbol at the start of a row (rows, 最近, settings): monochrome, outline,
/// regular, in ink2 whatever the row's state; scales with Dynamic Type like .title3 and is
/// centred in the row's icon column. Rows speak their title, so it is hidden from VoiceOver.
struct RowIcon: View {
    let symbol: String
    @ScaledMetric(relativeTo:.title3) private var size: CGFloat = 20
    var body: some View {
        Image(systemName:symbol)
            .font(.system(size:size, weight:.regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Theme.ink2)
            .accessibilityHidden(true)
    }
}
