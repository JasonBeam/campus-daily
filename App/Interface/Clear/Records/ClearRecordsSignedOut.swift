import SwiftUI

/// 记录 while signed out: 「登录后显示」 with 「登录学校账号」, which opens the first-run checklist
/// at 学校账号; under 「进行中」 when a shower or laundry order is still open.
struct ClearRecordsSignedOut: View {
    let open: [ClearOpenItem]
    @Environment(ClearNavigator.self) private var navigator

    var body: some View {
        if open.isEmpty {
            signIn
                .frame(maxWidth:.infinity, maxHeight:.infinity)
                .background(Color(uiColor:.systemGroupedBackground))
        } else {
            List {
                ClearOpenSection(items:open)
                signIn.listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var signIn: some View {
        ContentUnavailableView {
            Label("登录后显示", systemImage:"person.crop.circle")
        } actions: {
            Button { navigator.openSetup(at:.account, from:.cardRecords) } label: {
                Text("登录学校账号").font(.headline).padding(.horizontal,8).frame(minHeight:40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius:12))
            .tint(Theme.accent)
            .padding(.top,8)
            .accessibilityIdentifier("recordsSignIn")
        }
    }
}
