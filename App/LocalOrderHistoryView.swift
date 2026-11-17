import SwiftUI
import WaterCore

struct LocalOrderHistoryView: View {
    @EnvironmentObject private var water: WaterModel
    @EnvironmentObject private var laundry: LaundryModel
    @State private var records:[LocalOrderRecord]=[]
    @State private var issue:String?
    private var owners:[String:String] {["water":water.historyOwner ?? "", "laundry":laundry.historyOwner ?? ""]}
    private var visibleRecords:[LocalOrderRecord] {LocalOrderRecord.recent(records,owners:owners)}
    var body: some View {
        List {
            Section {
                Text("仅显示最近7×24小时在校日常保存的记录，不含官方小程序内产生的消费。状态为本机最后保存的结果。旧版未保存的记录无法补回；缺少账号归属的旧热水记录不纳入列表。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let issue { Section { Text(issue).foregroundStyle(.orange) } }
            if visibleRecords.isEmpty { Section { Text("近7天暂无可读取的本机记录").foregroundStyle(.secondary) } }
            ForEach(visibleRecords) { record in
                Section {
                    VStack(alignment:.leading,spacing:8) {
                        Text(record.title).font(.headline)
                        Text(record.startedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                        Text(record.status).font(.subheadline)
                        if let amount=record.amount {
                            Text(amount,format:.currency(code:"CNY")).monospacedDigit()
                        } else { Text("金额未确认").foregroundStyle(.secondary) }
                        Text(record.amountLabel).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,4)
                }
            }
        }.navigationTitle("近7天本机记录")
            .task(id:(water.historyOwner ?? "") + (laundry.historyOwner ?? "")) { load() }
            .refreshable { load() }
    }
    private func load() {
        // Import only records with explicit account provenance. No BLE or network requests.
        LocalOrderHistoryStore.record(laundry.checkout.flatMap(LocalOrderRecord.laundry))
        do {
            let store=try FileSessionStore()
            if let current=try store.load() { LocalOrderHistoryStore.record(.water(current)) }
            for previous in try store.loadArchive() {LocalOrderHistoryStore.record(.water(previous),onlyIfMissing:true)}
            records=try LocalOrderHistoryStore.load(owners:owners)
            issue=LocalOrderHistoryStore.issue
        } catch {issue="本机历史记录暂时无法读取，请稍后重试。"}
    }
}
