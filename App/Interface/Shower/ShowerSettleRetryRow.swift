import SwiftUI
import Core

/// 再结算一次 on the 不确定 face of a settlement that failed: the first tap arms it (the line
/// under it says the next tap sends it again), the second settles once more.
struct ShowerSettleRetryRow: View {
    @EnvironmentObject private var shower: ShowerModel
    private var flow: ShowerPageFlow { shower.page }
    private var armed: Bool { flow.settleRetryArmed }
    private var enabled: Bool { shower.mayRetrySettle && flow.mayRetrySettle }
    private var note: String { armed ? ShowerPageText.settleRetryArmedNote : ShowerPageText.settleRetryNote(flow.settleRetryCause) }

    var body: some View {
        VStack(alignment:.leading, spacing:4) {
            Button { shower.pageEvent(.settleRetryTapped) } label: {
                HStack(spacing:8) {
                    if shower.busy && shower.state.phase == .settling {
                        ProgressView().controlSize(.small).frame(width:16, height:16)
                    } else {
                        Image(systemName:armed ? "exclamationmark.arrow.circlepath" : "arrow.clockwise")
                            .scaledFont(15, relativeTo:.body)
                    }
                    Text(armed ? ShowerPageText.settleRetryConfirm : ShowerPageText.settleRetry).scaledFont(17, .medium)
                }
                .foregroundStyle(enabled ? Theme.accentText : Theme.ink3)
                .frame(minHeight:44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityIdentifier("showerSettleRetry")
            .accessibilityHint(note)
            Text(note)
                .scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal:false, vertical:true)
        }
    }
}
