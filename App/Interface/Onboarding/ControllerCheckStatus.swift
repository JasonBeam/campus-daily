import SwiftUI

/// What the controller check on the first-run 水控 step says (暖橙's guide and 清爽's 水控 page):
/// why it can't run now, a spinner while it runs, then what it found (errors in the login's
/// error style). Nothing before the first check.
struct ControllerCheckStatus: View {
    /// A shower is open or waits for its check: no check now.
    let blocked: String?
    let checking: Bool
    /// This page's check's answer (nil: none yet).
    let outcome: ShowerModel.InspectionOutcome?

    var body: some View {
        if let blocked, !checking {
            Label { Text(blocked).scaledFont(15, relativeTo:.subheadline) }
                icon: { Image(systemName:"info.circle").font(.system(size:17)) }
                .foregroundStyle(Theme.notice)
                .fixedSize(horizontal:false, vertical:true)
        } else if checking {
            HStack(spacing:10) {
                ProgressView().tint(Theme.ink2).frame(width:20, height:20)
                Text("正在找水控…").scaledFont(17, .medium).foregroundStyle(Theme.ink2)
            }
        } else if let outcome {
            if outcome == .verified {
                Label { Text(ShowerModel.inspectionVerifiedText).scaledFont(17, .medium).foregroundStyle(Theme.ink) }
                    icon: { Image(systemName:"checkmark.circle.fill").font(.system(size:22)).foregroundStyle(Theme.accentText) }
            } else {
                Label { Text(Self.text(outcome)).scaledFont(15, relativeTo:.subheadline) }
                    icon: { Image(systemName:"exclamationmark.circle.fill").font(.system(size:17)) }
                    .foregroundStyle(Theme.notice)
                    .fixedSize(horizontal:false, vertical:true)
            }
        }
    }

    static func text(_ outcome: ShowerModel.InspectionOutcome) -> String {
        switch outcome {
        case .verified: return ShowerModel.inspectionVerifiedText
        case .notFound: return "没找到水控，走近一点再试。"
        case .bluetoothOff: return ShowerPageText.bluetoothOff
        case .inUse: return ShowerModel.inspectionBusyText
        case .otherMachine: return "附近的水控不是你宿舍的那台。"
        case .failed(let text): return text
        }
    }
}
