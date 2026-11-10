import SwiftUI
import Core

/// 日常 tab root (清爽 home), under the large title 校园生活: the room, 双余额, 继续设置 while
/// something is not set, the 热水洗澡 and 洗衣机 tiles, the laundry order while one is open,
/// 上次热水 once a shower was settled, and the pull hint. The settings button opens 设置 as a sheet.
///
/// Pages open through `ClearNavigator`; the root hosts the shower page, the laundry-done sheet
/// and the sign-in sheet.
struct ClearHomeView: View {
    @EnvironmentObject var shower: ShowerModel
    @EnvironmentObject var campus: CampusModel
    @EnvironmentObject var laundry: LaundryModel
    @Environment(ClearNavigator.self) var navigator
    @Environment(SampleMode.self) var sample
    @Environment(\.dynamicTypeSize) var typeSize
    /// The dorm confirmed on the checklist (a dorm may have no controller to bind).
    @AppStorage(SetupChecklist.dormKey) var confirmedDorm = ""
    @State private var settingsShown = false

    var body: some View {
        let data = navigator.data(campus:campus, shower:shower, laundry:laundry)
        // Not `.scrollBounceBehavior(.basedOnSize)`: content that fits must still bounce for the pull.
        ScrollView {
            VStack(alignment:.leading, spacing:18) {
                ClearRoomLine(room:ClearBalanceText.room(data.signedIn ? data.dorm : nil), refreshing:data.refreshing)
                ClearBalanceCard(data:data)
                setupCard(data)
                tiles(data)
                if let order = data.laundryOrder {
                    ClearHomeOrderCard(line:order) { navigator.push(.laundry) }
                }
                if let ended = data.lastShowerEnded {
                    ClearLastShowerCard(ended:ended, cost:data.lastShowerCost)
                }
                Text(ClearBalanceText.pullHint).font(.caption).foregroundStyle(Theme.ink2).padding(.horizontal,4)
            }
            .padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(ClearBalanceText.homeTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Button { settingsShown = true } label: {
                    Image(systemName:"slider.horizontal.3").frame(width:44, height:44)
                }
                .accessibilityLabel("设置与个人配置")
            }
        }
        .sheet(isPresented:$settingsShown) { settingsSheet }
        // A settings row that opens a page on 日常 (热水, 继续设置) takes the sheet down.
        .onChange(of:navigator.homePath) { _, _ in settingsShown = false }
        .onChange(of:navigator.tab) { _, _ in settingsShown = false }
        // SwiftUI may cancel the pull's own task when the page changes under it: the read runs
        // on its own and the pull waits for it.
        .refreshable { await Task { await pull() }.value }
    }

    private var settingsSheet: some View {
        NavigationStack {
            ClearSettingsTab()
                .navigationDestination(for:ClearRoute.self) { ClearDestination(route:$0) }
                .toolbar {
                    ToolbarItem(placement:.confirmationAction) { Button("完成") { settingsShown = false } }
                }
        }
        .environment(navigator)
        .typesettingLanguage(Theme.typesetting)
        .navOpen(.settings, from:.homeButton)
    }

    @ViewBuilder func setupCard(_ data: HomeData) -> some View {
        let dormSet = SetupChecklist.isDormSet(dorm:data.dorm, confirmedDorm:confirmedDorm,
                                               controllerBound:data.shower != .unconfigured)
        if let detail = HomeSetupCard.detail(signedIn:data.signedIn, dormSet:dormSet,
                                             laundryEnabled:data.laundryEnabled, laundryBound:data.laundryBound) {
            ClearSetupCard(detail:detail) { navigator.push(.setupChecklist) }
        }
    }

    /// Pull to refresh: the school's numbers, then the washer.
    func pull() async {
        // The sample reads nothing: the pull only shows.
        if sample.isActive { try? await Task.sleep(for:.milliseconds(700)); return }
        await campus.refresh(force:true)
        await laundry.refresh(force:true)
    }
}
