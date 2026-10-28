import SwiftUI
import WaterCore

struct CampusPowerSetupView: View {
    @EnvironmentObject private var campus: CampusModel
    @Environment(\.dismiss) private var dismiss
    @State private var options: [CampusPowerBuilding] = []
    @State private var meters: [CampusElectricity] = []
    @State private var path: [CampusPowerBuilding] = []
    @State private var busy = false
    @State private var issue: String?
    @State private var search = ""
    private let provider = CampusProvider()
    var body: some View {
        List {
            Section {
                Text(path.isEmpty ? "选择校区、楼栋和寝室" : path.map(\.name).joined(separator:" · "))
                    .font(.headline)
                Text("电表与热水水控是独立绑定，核对寝室后再保存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if busy { Text("正在读取电表信息…").foregroundStyle(.secondary) }
            if let issue { Text(issue).foregroundStyle(.orange).font(.footnote) }
            Section(meters.isEmpty ? "选择位置" : "核对电表") {
                ForEach(options.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { option in
                    Button(option.name) { Task { await choose(option) } }.disabled(busy)
                }
                ForEach(meters) { meter in
                    Button {
                        guard let building = path.last else { return }
                        do { try campus.savePowerBinding(building:building.id,meter:meter); Task { await campus.refresh(force:true) }; dismiss() }
                        catch { issue = "暂未保存，请稍后重试" }
                    } label: {
                        VStack(alignment:.leading,spacing:8) {
                            Text(meter.room).font(.headline)
                            Text("剩余 \(NSDecimalNumber(decimal:meter.remainingKWh).stringValue) 度 · 电费 \(NSDecimalNumber(decimal:meter.balanceYuan).stringValue) 元")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("确认是我的寝室并保存").font(.footnote)
                        }.padding(.vertical,8)
                    }.disabled(busy)
                }
            }
            if !path.isEmpty { Button("重新选择位置") { Task { await loadRoot() } }.disabled(busy) }
        }.scrollContentBackground(.hidden).background(NothingTheme.background).tint(NativeTheme.tint)
            .navigationTitle("绑定宿舍电表").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$search,prompt:"搜索楼栋或寝室")
            .task { await loadRoot() }
    }
    private func loadRoot() async {
        guard !busy, let config = campus.onboardingLogin else { issue = "请先登录学校账号"; return }
        busy = true; issue = nil; path = []; meters = []; search = ""
        defer { busy = false }
        do { options = try await provider.powerBuildings(config:config) }
        catch { issue = (error as? LocalizedError)?.errorDescription ?? "位置列表读取失败" }
    }
    private func choose(_ option: CampusPowerBuilding) async {
        guard !busy, let config = campus.onboardingLogin else { return }
        busy = true; issue = nil; search = ""
        defer { busy = false }
        do {
            let children = try await provider.powerBuildings(config:config,parent:option.id)
            path.append(option); options = children
            if children.isEmpty {
                meters = try await provider.powerMeters(config:config,building:option.id)
                if meters.isEmpty { issue = "此位置没有返回电表，请重新选择" }
            }
        } catch { issue = (error as? LocalizedError)?.errorDescription ?? "电表读取失败，请重试" }
    }
}
