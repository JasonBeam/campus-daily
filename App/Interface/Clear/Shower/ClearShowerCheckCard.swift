import SwiftUI
import Core

/// 2.5: under the check or the 不确定 face, the read-only 再查一次水控 and, after a settlement
/// that failed, 再结算一次, in a card. Nothing to show: no card.
struct ClearShowerCheckCard: View {
    @EnvironmentObject private var shower: ShowerModel

    private var flow: ShowerPageFlow { shower.page }

    var body: some View {
        if flow.showsRecheck || flow.mayRetrySettle {
            VStack(alignment:.leading, spacing:12) {
                if flow.showsRecheck { ShowerRecheckRow() }
                if flow.mayRetrySettle { ShowerSettleRetryRow() }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth:.infinity, alignment:.leading)
            .background(NativeTheme.surface, in:RoundedRectangle(cornerRadius:16, style:.continuous))
        }
    }
}
