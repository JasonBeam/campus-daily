import SwiftUI
import WaterCore

struct LaundryDetail: View {
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(\.scenePhase) private var phase
    @State private var selectedId: Int?
    @State private var draft: LaundryProgram?
    @State private var review = false
    @State private var confirmPayment = false
    @State private var confirmCancellation = false
    private let accent = NativeTheme.tint
    private var selected: LaundryProgram? {
        laundry.snapshot?.programs.first(where: { $0.id == selectedId }) ?? laundry.snapshot?.programs.first
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if let value = laundry.snapshot {
                    deviceCard(value)
                    if let record = laundry.checkout {
                        if record.stage == .completed {
                            HStack {
                                Text(record.order?.label ?? "上次订单已结束").font(.subheadline)
                                Spacer()
                                Text(record.order?.paid == true ? "已付款" : "未支付").font(.caption).foregroundStyle(.secondary)
                            }.padding(16).background(NothingTheme.surface,in:RoundedRectangle(cornerRadius:18))
                        } else { orderCard(record) }
                    }
                    if laundry.checkout == nil || laundry.checkout?.stage == .completed {
                    HStack {
                        Text("选择程序").font(.title3.weight(.semibold))
                        Spacer()
                        Text("按当前价格").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal,4)
                    VStack(spacing:10) {
                        ForEach(value.programs) { program in programRow(program) }
                    }
                    }
                } else {
                    ContentUnavailableView(laundry.configured ? "等待设备信息" : "尚未配置洗衣机",
                        systemImage:"washer",description:Text(laundry.configured ? "下拉刷新查看机器" : "先登录 U净，再扫码添加常用机器"))
                    NavigationLink("设置常用洗衣机") { WasherSetupView() }
                }
                if let issue = laundry.issue { Label(issue,systemImage:"exclamationmark.circle").font(.footnote).foregroundStyle(.orange) }
                if laundry.checkout == nil, let issue = laundry.checkoutIssue { Text(issue).font(.footnote).foregroundStyle(.orange) }
                if laundry.checkout == nil || laundry.checkout?.stage == .completed {
                    Text("先放好衣物。确认机器与程序后再下单，付款可能使设备开始运行。")
                        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            }.padding(20).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(NativeTheme.background).tint(NativeTheme.tint)
            .navigationTitle("洗衣机").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button { Task { await laundry.refresh(force:true); await laundry.refreshOrder() } } label: {
                        if laundry.loading || laundry.checkoutBusy { ProgressView() }
                        else { Image(systemName:"arrow.clockwise").frame(width:44,height:44) }
                    }.disabled(laundry.loading || laundry.checkoutBusy).accessibilityLabel("刷新洗衣机")
                }
            }
            .safeAreaInset(edge:.bottom) {
                if laundry.configured && (laundry.checkout == nil || laundry.checkout?.stage == .completed) {
                    Button {
                        Task {
                            await laundry.refresh(force:true)
                            guard laundry.mayCreate, let value = selected else { return }
                            draft = value; review = true
                        }
                    } label: {
                        HStack {
                            if laundry.checkoutBusy { ProgressView().controlSize(.small) }
                            Text(laundry.checkoutBusy ? (laundry.checkoutProgress ?? "正在处理…") : (laundry.loading ? "正在核对" : "确认程序"))
                            Spacer()
                            if !laundry.checkoutBusy {
                                if let selected { Text(selected.price,format:.currency(code:"CNY")).monospacedDigit() }
                                Image(systemName:"arrow.right")
                            }
                        }.padding(.horizontal,18).frame(minHeight:54)
                    }.buttonStyle(WaterButtonStyle(primary:true,accent:accent))
                        .disabled(!laundry.mayCreate).padding(.horizontal,20).padding(.vertical,12)
                        .background(NativeTheme.background).accessibilityIdentifier("reviewLaundryOrder")
                }
            }
            .task { await laundry.refresh(); await laundry.refreshOrder() }
            .refreshable { await laundry.refresh(force:true); await laundry.refreshOrder() }
            .sheet(isPresented:$review) {
                if let draft, let value = laundry.snapshot {
                    LaundryReviewSheet(program:draft,machine:"\(value.storeName) · \(value.deviceNo)号") {
                        review = false
                        Task { await laundry.createAndPay(draft) }
                    }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
                }
            }
            .alert("确认支付宝付款",isPresented:$confirmPayment) {
                Button("确认付款") { Task { await laundry.pay() } }
                Button("暂不付款",role:.cancel) {}
            } message: {
                Text("付款可能扣款并启动这台洗衣机。请确认衣物已放好，实际金额以支付宝收银台为准。")
            }
            .sheet(isPresented:$confirmCancellation) {
                LaundryCancellationSheet(program:laundry.checkout?.programName ?? "当前程序") {
                    confirmCancellation = false
                    Task { await laundry.cancelOrder() }
                }.presentationDetents([.medium,.large]).presentationDragIndicator(.visible)
            }
    }
    private func deviceCard(_ value: LaundrySnapshot) -> some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top,spacing:14) {
                Image(systemName:"washer").font(.title).foregroundStyle(accent)
                    .frame(width:52,height:52).background(accent.opacity(0.08),in:RoundedRectangle(cornerRadius:16))
                VStack(alignment:.leading,spacing:6) {
                    Text("\(value.deviceNo)号 · \(value.deviceTypeName)").font(.headline)
                    Text(value.storeName).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack {
                Label(laundry.deviceStateText,systemImage:"circle.fill").font(.caption.weight(.medium)).foregroundStyle(accent)
                Spacer()
                Text(laundry.freshness).font(.caption).foregroundStyle(.secondary)
            }
            Text("查询于 \(value.fetchedAt.formatted(date:.omitted,time:.standard))").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            .background(NothingTheme.surface,in:RoundedRectangle(cornerRadius:16))
    }
    private func programRow(_ program: LaundryProgram) -> some View {
        let isSelected = selected?.id == program.id
        return Button { selectedId = program.id } label: {
            HStack(alignment:.center,spacing:14) {
                Image(systemName:isSelected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(isSelected ? accent : Color.secondary)
                VStack(alignment:.leading,spacing:6) {
                    Text(program.workModelName).font(.headline).foregroundStyle(.primary)
                    Text("\(program.time)分钟").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength:8)
                Text(program.price,format:.currency(code:"CNY")).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
            }.padding(18).frame(maxWidth:.infinity,minHeight:82)
                .background(isSelected ? accent.opacity(0.08) : NothingTheme.surface,in:RoundedRectangle(cornerRadius:16))
                .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(isSelected ? accent.opacity(0.5) : .clear,lineWidth:1))
        }.buttonStyle(.plain).disabled(laundry.checkoutBusy)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    private func orderCard(_ record: LaundryCheckoutRecord) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Text(record.stage == .completed ? "上次洗衣订单" : "当前洗衣订单").font(.subheadline).foregroundStyle(.secondary)
            Text(record.order?.label ?? "正在核对预约结果").font(.headline)
            Text(record.order?.payPrice ?? record.expectedPrice,format:.currency(code:"CNY"))
                .font(.system(.largeTitle,design:.rounded).weight(.semibold)).monospacedDigit()
            Text("实际金额以支付宝收银台为准").font(.caption).foregroundStyle(.secondary)
            LabeledContent("洗衣程序",value:record.programName).font(.subheadline)
            if record.order?.payFlag?.text == "0" { Text("未支付").font(.caption).foregroundStyle(.secondary) }
            if let issue = laundry.checkoutIssue { Text(issue).font(.footnote).foregroundStyle(.orange) }
            if let progress = laundry.checkoutProgress {
                HStack(spacing:9) {
                    if laundry.checkoutBusy { ProgressView().controlSize(.small) }
                    else { Image(systemName:"arrow.up.right.square") }
                    Text(progress).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let order = record.order, order.status.text == "10", let seconds = order.countDown, seconds > 0 {
                TimelineView(.periodic(from:.now,by:1)) { context in
                    let remaining = max(0,seconds - Int(context.date.timeIntervalSince(record.orderUpdatedAt ?? record.createdAt)))
                    Text(remaining > 0 ? String(format:"%02d:%02d 后自动取消",remaining / 60,remaining % 60) : "等待服务器确认预约状态")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let order = record.order, order.running, let seconds = order.remainTime, seconds > 0 {
                Text("剩余约 \((seconds + 59) / 60)分钟").font(.subheadline)
            }
            if record.stage == .created, let order = record.order,
               ["10","17"].contains(order.status.text), order.payFlag?.text == "0" {
                Text("请先放好衣物，付款可能启动洗衣机。").font(.footnote).foregroundStyle(.secondary)
                Button { confirmPayment = true } label: {
                    Label("前往支付宝",systemImage:"arrow.up.right.square").frame(maxWidth:.infinity,minHeight:50)
                }.buttonStyle(WaterButtonStyle(primary:true,accent:accent)).disabled(laundry.checkoutBusy)
            }
            Button { Task { await laundry.refreshOrder() } } label: {
                Label(laundry.checkoutBusy ? "正在处理" : "刷新订单状态",systemImage:"arrow.clockwise")
                    .frame(maxWidth:.infinity,minHeight:44)
            }.disabled(laundry.checkoutBusy)
            if laundry.mayCancel {
                Button(role:.destructive) { confirmCancellation = true } label: {
                    Label("取消订单",systemImage:"xmark.circle").frame(maxWidth:.infinity,minHeight:44)
                }.accessibilityIdentifier("cancelLaundryOrder")
            }
            if record.stage == .creating || record.stage == .cancellationRequested ||
               (record.stage == .paymentRequested && record.order?.paid != true && record.order?.running != true) {
                Text("结果未确认时请勿重复下单或付款，可在U净订单中核对。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).background(NothingTheme.surface,in:RoundedRectangle(cornerRadius:16))
            .task(id:record.orderUpdatedAt) {
                if let order = record.order, order.status.text == "10", let seconds = order.countDown, seconds > 0 {
                    do { try await Task.sleep(for:.seconds(seconds + 1)) } catch { return }
                    await laundry.refreshOrder()
                }
            }
    }
}

private struct LaundryCancellationSheet: View {
    let program: String
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false
    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:24) {
                Text("取消这次预约？").font(.title2.weight(.semibold))
                Text(program).font(.headline)
                Text("取消后将释放预约。此操作仅适用于尚未支付的订单。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(role:.destructive) { submitted = true; confirm() } label: {
                    Text("确认取消订单").frame(maxWidth:.infinity,minHeight:52)
                }.buttonStyle(.borderedProminent).tint(.red).disabled(submitted)
                    .accessibilityIdentifier("confirmCancelLaundryOrder")
                Spacer(minLength:0)
            }.padding(24).navigationTitle("取消订单").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("保留订单") { dismiss() } } }
        }
    }
}

private struct LaundryReviewSheet: View {
    let program: LaundryProgram
    let machine: String
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VStack(alignment:.leading,spacing:8) {
                        Text(machine).font(.headline)
                        Text("\(program.workModelName) · \(program.time)分钟").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(alignment:.firstTextBaseline) {
                        Text("预计金额").foregroundStyle(.secondary)
                        Spacer()
                        Text(program.price,format:.currency(code:"CNY")).font(.largeTitle.weight(.semibold)).monospacedDigit()
                    }
                    Text("确认后将预约这台机器并前往支付宝。付款可能扣款并启动设备，请提前放好衣物，实际金额以收银台为准。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button { submitted = true; confirm() } label: {
                        Text("下单并前往支付宝").frame(maxWidth:.infinity,minHeight:52)
                    }.buttonStyle(WaterButtonStyle(primary:true,accent:Color.primary))
                        .disabled(submitted).accessibilityIdentifier("submitLaundryOrder")
                }.padding(24)
            }.navigationTitle("核对订单").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
