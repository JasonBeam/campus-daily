import SwiftUI

/// 衣服洗好了, the sheet the root shows once per finished laundry order (`navigator.panel`; the
/// root gives it the medium detent and drag indicator, and closes it when the shower page comes
/// up). 「好」 closes it.
struct ClearLaundryDonePanel: View {
    @Environment(ClearNavigator.self) private var navigator

    var body: some View {
        VStack(spacing:12) {
            if case .laundryDone(let amount, let detail)? = navigator.panel {
                Image(systemName:"checkmark.circle.fill")
                    .font(.system(size:44)).foregroundStyle(Theme.accentText)
                    .accessibilityHidden(true)
                Text("衣服洗好了").font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let amount {
                    Text(Theme.yuan(amount)).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                }
                Text(detail).font(.subheadline).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal,20).padding(.top,32)
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.top)
        .safeAreaInset(edge:.bottom) {
            Button { navigator.panel = nil } label: {
                HStack { Text("好"); Spacer(minLength:0) }
            }
            .buttonStyle(ClearHomePrimaryStyle())
            .padding(.horizontal,20).padding(.vertical,12)
            .accessibilityIdentifier("laundryDoneOK")
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
