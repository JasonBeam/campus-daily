import SwiftUI

/// Laundry result panel: custom bottom panel over a 0.2 dim.
struct SettlementPanel: View {
    let result: SettlementResult
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing:0) {
            switch result {
            case .laundryDone(let amount, let detail):
                Mascot(size:52)
                Text("衣服洗好了").scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2).padding(.top,10)
                if let amount {
                    Text(Theme.yuan(amount)).scaledFont(44, .semibold, design:.rounded, relativeTo:.largeTitle)
                        .monospacedDigit().tracking(-1).foregroundStyle(Theme.ink).padding(.top,4)
                }
                if !detail.isEmpty {
                    Text(detail).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2).padding(.top,4)
                }
            }
            Button(action:dismiss) {
                Text("好").scaledFont(17, .semibold, relativeTo:.headline).foregroundStyle(Theme.ink)
                    .frame(maxWidth:.infinity).frame(minHeight:50)
                    .background(Theme.fill, in:Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("好，关闭")
            .padding(.top,18)
        }
        .multilineTextAlignment(.center)
        .padding(.top,26).padding(.horizontal,24).padding(.bottom,24)
        .frame(maxWidth:.infinity)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:40, style:.continuous))
        .accessibilityElement(children:.contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Dim + panel, sliding up from below.
struct SettlementOverlay: View {
    @Binding var result: SettlementResult?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment:.bottom) {
            if let value = result {
                Color.black.opacity(0.2).ignoresSafeArea()
                    .onTapGesture { result = nil }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                SettlementPanel(result:value) { result = nil }
                    .padding(12)
                    .transition(reduceMotion ? .opacity : .move(edge:.bottom))
            }
        }
        .ignoresSafeArea(edges:.bottom)
        .animation(Theme.spring, value:result)
    }
}
