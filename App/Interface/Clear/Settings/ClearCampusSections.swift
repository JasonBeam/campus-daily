import SwiftUI
import Core

/// The top of 清爽's 校园登录与宿舍 (`AccountView(places:)`): 学校登记宿舍, 宿舍电表 and 宿舍热水,
/// each opening its page (热水, once bound, the shower page on 日常).
struct ClearCampusSections: View {
    let data: HomeData
    @Environment(ClearNavigator.self) private var navigator
    @EnvironmentObject private var laundry: LaundryModel

    var body: some View {
        if data.signedIn {
            Section("学校登记宿舍") {
                NavigationLink(value:ClearRoute.dorm) {
                    Text(data.dormLocation ?? data.dorm ?? "选择宿舍").foregroundStyle(data.dormLocation ?? data.dorm == nil ? Theme.accentText : Theme.ink)
                }
                .accessibilityIdentifier("campusDorm")
            }.listRowBackground(Theme.group)
            Section("宿舍电表") {
                NavigationLink(value:ClearRoute.powerSetup) {
                    if data.powerBound { done("电表已保存") } else { Text("绑定宿舍电表").foregroundStyle(Theme.accentText) }
                }
                .accessibilityIdentifier("campusMeter")
            }.listRowBackground(Theme.group)
        }
        Section("宿舍热水") {
            if data.shower == .unconfigured {
                // Hot water is bound by choosing the dorm (the controller), not by a file.
                NavigationLink(value:ClearRoute.dorm) { Text("选择宿舍与水控").foregroundStyle(Theme.accentText) }
                    .accessibilityIdentifier("campusHotWater")
            } else {
                Button {
                    navigator.showShowerPage(laundry:laundry.checkout?.phase, from:.settings)
                } label: {
                    HStack {
                        done("水控已绑定")
                        Spacer()
                        Image(systemName:"chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink3)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("campusHotWater")
            }
        }.listRowBackground(Theme.group)
    }

    /// A green check and what is saved.
    private func done(_ title: String) -> some View {
        Label(title, systemImage:"checkmark.circle").foregroundStyle(.green)
    }
}
