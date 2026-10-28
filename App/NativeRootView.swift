import SwiftUI

struct CampusRootView: View {
    var body: some View {
        TabView {
            WaterHome().tabItem { Label("日常",systemImage:"square.grid.2x2") }
            RecentOrdersView().tabItem { Label("订单",systemImage:"clock.arrow.circlepath") }
            SettingsView(showsDone:false).tabItem { Label("设备",systemImage:"slider.horizontal.3") }
        }.tint(NativeTheme.tint)
    }
}

private struct RecentOrdersView: View {
    @EnvironmentObject private var water: WaterModel
    @EnvironmentObject private var laundry: LaundryModel
    var body: some View {
        NavigationStack {
            List {
                if let record = laundry.checkout {
                    Section("最近洗衣订单") {
                        NavigationLink { LaundryDetail() } label: {
                            VStack(alignment:.leading,spacing:8) {
                                Text(record.order?.label ?? "订单待核对").font(.headline)
                                Text(record.programName).font(.subheadline).foregroundStyle(.secondary)
                                Text(record.order?.payPrice ?? record.expectedPrice,format:.currency(code:"CNY")).monospacedDigit()
                            }.padding(.vertical,6)
                        }
                    }
                }
                if let stage = water.stage, stage != .settled {
                    Section("当前热水记录") {
                        NavigationLink { WaterDetail() } label: {
                            VStack(alignment:.leading,spacing:6) {
                                Text("热水洗澡").font(.headline)
                                Text(stage.label).font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical,6)
                        }
                    }
                }
                if let ended = water.lastEnded {
                    Section("最近热水结算") {
                        NavigationLink { WaterDetail() } label: {
                            HStack {
                                VStack(alignment:.leading,spacing:6) {
                                    Text("热水已结算")
                                    Text(ended.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let cost = water.lastCost { Text(cost,format:.currency(code:"CNY")).monospacedDigit() }
                                else { Text("金额未返回").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.vertical,6)
                        }
                    }
                }
                if laundry.checkout == nil && water.lastEnded == nil && (water.stage == nil || water.stage == .settled) {
                    ContentUnavailableView("还没有使用记录",systemImage:"clock",description:Text("在本 App 使用热水或洗衣后，最近记录会显示在这里。"))
                        .listRowBackground(Color.clear)
                }
            }.navigationTitle("最近订单")
                .refreshable { await laundry.refreshOrder() }
        }
    }
}
