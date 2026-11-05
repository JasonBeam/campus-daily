import SwiftUI

/// The 设置 tab's top row: opens the first-run checklist (首次设置), pushed on this tab. In the
/// sample it only says so (signing in is 去登录, on the bar).
struct ClearSetupEntry: View {
    var body: some View {
        SampleGatedRow(action:.schoolAccount) {
            NavigationLink(value:ClearRoute.setupChecklist) { label }
        } label: {
            SampleRowLabel(row:label)
        }
        .accessibilityIdentifier("quickSetupEntry")
    }

    private var label: some View {
        VStack(alignment:.leading, spacing:8) {
            Text("首次设置").font(.caption).foregroundStyle(Theme.ink2)
            Text("学校账号、宿舍和洗衣机").font(.headline).foregroundStyle(Theme.ink)
            Text("跟着清单登录、选宿舍、扫洗衣机。").font(.footnote).foregroundStyle(Theme.ink2)
        }
        .padding(.vertical,10)
    }
}
