import SwiftUI
import Core

/// 洗衣 in 清爽, pushed on the 日常 stack: the machine's card, then its programs or the open
/// order, and 「下单」 at the bottom. Ordering, paying, cancelling and checking are the model's
/// (`LaundryModel`); this page decides what to show and forwards the user's confirmations, as
/// 暖橙's `LaundryDetail` does.
/// DEBUG demos put their laundry state in `navigator.laundryDemo`. The root keeps this page up
/// for links and notification taps while an order is being paid (`WidgetLink.mayClosePages`).
struct ClearLaundryPage: View {
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(ClearNavigator.self) private var navigator
    @ObservedObject private var reminders = Reminders.shared
    @State private var selectedID: Int?
    @State private var sheet: LaundrySheet?
    /// 重新登录 U净, from an expired login.
    @State private var relogin = false
    /// A confirmed create/pay sequence is running (covers the gap between its two steps).
    @State private var submitting = false
    /// Re-reading the machine right before the confirmation sheet.
    @State private var preparing = false

    private var isDemo: Bool {
        #if DEBUG
        return navigator.laundryDemo != nil
        #else
        return false
        #endif
    }

    private var facts: LaundryFacts {
        #if DEBUG
        if let demo = navigator.laundryDemo { return demo.facts }
        #endif
        return LaundryFacts(model:laundry)
    }

    /// Only promise 洗好了会通知你 when the reminder is on and notifications are allowed.
    private var notifiesWhenDone: Bool {
        #if DEBUG
        if let demo = navigator.laundryDemo { return demo.notify }
        #endif
        return reminders.laundryDoneWillNotify
    }

    var body: some View {
        let facts = facts
        let phase = facts.phase()
        let busyTitle = busyTitle(facts, phase:phase)
        ScrollView {
            VStack(alignment:.leading, spacing:20) {
                content(facts, phase:phase, busyTitle:busyTitle)
                ClearLaundryIssueLines(lines:ClearLaundryCopy.issues(facts, shown:shownLine(facts, phase:phase)))
                if facts.sessionExpired {
                    Button(UjingAccountText.relogin) { relogin = true }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
                        .frame(maxWidth:.infinity, alignment:.leading)
                        .accessibilityIdentifier("ujingRelogin")
                }
            }
            .padding(20)
            .frame(maxWidth:560)
            .frame(maxWidth:.infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("洗衣")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(facts, phase:phase) }
        .safeAreaInset(edge:.bottom, spacing:0) { dock(facts, phase:phase, busyTitle:busyTitle) }
        // SwiftUI may cancel the pull's own task when the page changes under it (the read
        // starting does): the read runs on its own and the pull waits for it.
        .refreshable { await Task { await reload() }.value }
        .task {
            #if DEBUG
            if let initial = navigator.laundryDemo?.sheet {
                try? await Task.sleep(for:.milliseconds(450))
                sheet = initial == .cancel ? .cancel : confirmSheet(self.facts, newOrder:true)
                return
            }
            #endif
            guard !isDemo else { return }
            await laundry.refresh(); await laundry.refreshOrder()
        }
        // Unpaid reservation: re-read once the server's auto-cancel countdown passes.
        .task(id:facts.record?.orderReadAt) {
            guard !isDemo, let record = self.facts.record, record.inFlight, let order = record.order,
                  order.status.code == "10", let seconds = order.countDown, seconds > 0 else { return }
            do { try await Task.sleep(for:.seconds(seconds + 1)) } catch { return }
            await laundry.refreshOrder()
        }
        .sheet(item:$sheet) { item in sheetView(item, facts:facts).typesettingLanguage(Theme.typesetting) }
        .sheet(isPresented:$relogin) { UjingLoginView() }
        // A lookup after the sheet came up (back from the U净 app) found something other than
        // no order: the clear is no longer allowed, so its sheet goes instead of doing nothing.
        .onChange(of:facts.record?.canResolveManually == true) { _, allowed in
            if !allowed, sheet == .resolve { sheet = nil }
        }
        .sensoryFeedback(.selection, trigger:selectedID)
    }

    /// The model's progress while it works on an order from this page (「正在下单…」, 「正在打开支付宝…」).
    private func busyTitle(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> String? {
        let shows: Bool
        switch phase {
        case .idle, .done, .unpaid, .check: shows = true
        default: shows = false
        }
        guard submitting || (facts.busy && shows) else { return nil }
        return facts.progress ?? (submitting ? "正在下单…" : "正在核对订单…")
    }

    /// The sentence the page already shows, so an error line doesn't repeat it.
    private func shownLine(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> String? {
        ClearLaundryCopy.orderCaption(facts, phase:phase, notify:notifiesWhenDone)?.text
    }

    // MARK: Content

    @ViewBuilder private func content(_ facts: LaundryFacts, phase: LaundryFacts.Phase, busyTitle: String?) -> some View {
        switch phase {
        case .empty, .unknown:
            ClearLaundryEmptyView(unread:phase == .unknown) { navigator.push(.washerSetup) }
                .padding(.top,40)
        default:
            if let snapshot = facts.snapshot {
                ClearLaundryDeviceCard(snapshot:snapshot, state:ClearLaundryCopy.deviceState(facts),
                                       problem:ClearLaundryCopy.isProblem(phase))
            }
            if let line = ClearLaundryCopy.unavailableLine(facts, phase:phase) {
                Text(line).font(.subheadline).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.horizontal,4)
            }
            switch phase {
            case .idle, .done:
                programs(facts, selectable:true, enabled:busyTitle == nil && !preparing, dimmed:busyTitle != nil)
                Text(ClearLaundryCopy.caution).font(.footnote).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.horizontal,4)
            case .inUse, .unavailable:
                programs(facts, selectable:false, enabled:false, dimmed:true)
            default:
                if facts.record != nil {
                    ClearLaundryOrderCard(facts:facts, phase:phase, notify:notifiesWhenDone, busyTitle:busyTitle,
                                          pay:{ sheet = confirmSheet(facts, newOrder:false) },
                                          cancel:{ sheet = .cancel },
                                          check:{ check(failedStart:phase == .check(failedStart:true)) },
                                          resolve:{ sheet = .resolve })
                }
            }
        }
    }

    @ViewBuilder private func programs(_ facts: LaundryFacts, selectable: Bool, enabled: Bool, dimmed: Bool) -> some View {
        if let programs = facts.snapshot?.programs, !programs.isEmpty {
            ClearLaundryProgramList(programs:programs, selectedID:selectable ? selected(facts)?.id : nil,
                                    enabled:enabled, dimmed:dimmed) { selectedID = $0 }
        }
    }

    private func selected(_ facts: LaundryFacts) -> WasherProgram? {
        guard let programs = facts.snapshot?.programs else { return nil }
        if let selectedID, let match = programs.first(where:{ $0.id == selectedID }) { return match }
        if let device = facts.snapshot?.deviceID {
            let last = UserDefaults.standard.integer(forKey:LaundryDetail.lastProgramKey(device))
            if let match = programs.first(where:{ $0.id == last }) { return match }
        }
        return programs.first
    }

    // MARK: Toolbar and dock

    @ToolbarContentBuilder private func toolbar(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> some ToolbarContent {
        if facts.loading {
            ToolbarItem(placement:.topBarTrailing) {
                ProgressView().frame(width:44, height:44).accessibilityLabel("正在更新…")
            }
        } else if phase != .empty, phase != .unknown {
            ToolbarItem(placement:.topBarTrailing) {
                NavigationLink(value:ClearRoute.washerSetup) {
                    Image(systemName:"qrcode.viewfinder").frame(width:44, height:44)
                }
                .accessibilityLabel(ClearLaundryCopy.isProblem(phase) ? "扫另一台洗衣机" : "扫洗衣机")
                .accessibilityIdentifier("laundryScan")
            }
        }
    }

    @ViewBuilder private func dock(_ facts: LaundryFacts, phase: LaundryFacts.Phase, busyTitle: String?) -> some View {
        switch phase {
        case .idle, .done:
            let program = selected(facts)
            let title = "下单" + (program.map { " · " + Theme.yuan($0.price.yuan) } ?? "")
            dockBar {
                Button { order() } label: {
                    ClearLaundryButtonLabel(title:busyTitle ?? title, symbol:"arrow.right",
                                            busy:busyTitle != nil || preparing, minHeight:54)
                }
                .buttonStyle(ClearLaundryPrimaryStyle())
                .disabled(busyTitle != nil || !facts.mayCreate || preparing || program == nil)
                .accessibilityLabel(busyTitle ?? program.map { "下单，" + LaundryFormat.spokenYuan($0.price.yuan) } ?? "下单")
                .accessibilityIdentifier("reviewLaundryOrder")
            }
        case .inUse, .unavailable:
            dockBar {
                ClearLaundryButtonLabel(title:ClearLaundryCopy.unavailableTitle(phase), minHeight:54)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentInk)
                    .background(Theme.accent, in:RoundedRectangle(cornerRadius:12, style:.continuous))
                    .opacity(0.4)
                    .accessibilityElement(children:.combine)
                    .accessibilityAddTraits(.isStaticText)
            }
        default:
            EmptyView()
        }
    }

    private func dockBar(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.horizontal,20).padding(.vertical,12)
            .frame(maxWidth:560)
            .frame(maxWidth:.infinity)
            .background(Theme.bg.ignoresSafeArea(edges:.bottom))
    }

    // MARK: Sheets

    private func confirmSheet(_ facts: LaundryFacts, newOrder: Bool) -> LaundrySheet? {
        if newOrder {
            guard let program = selected(facts) else { return nil }
            return .confirm(program:program, newOrder:true)
        }
        return .confirm(program:nil, newOrder:false)
    }

    @ViewBuilder private func sheetView(_ item: LaundrySheet, facts: LaundryFacts) -> some View {
        switch item {
        case .confirm(let program, let newOrder):
            ClearLaundryPaySheet(title:newOrder ? "下单并去支付宝付款？" : "去支付宝付款？",
                                 machine:ClearLaundryCopy.machineLine(facts),
                                 program:program.map(LaundryFormat.program) ?? ClearLaundryCopy.programLine(facts),
                                 amount:program?.price.yuan ?? facts.amount) {
                sheet = nil
                if newOrder, let program { submit(program) } else { payExisting() }
            }
        case .cancel:
            ClearLaundryConfirmSheet.cancel(order:ClearLaundryCopy.orderTitle(facts)) {
                sheet = nil
                cancel()
            }
        case .resolve:
            ClearLaundryConfirmSheet.resolve(order:ClearLaundryCopy.orderTitle(facts)) {
                sheet = nil
                resolve()
            }
        }
    }

    // MARK: Actions

    private func reload() async {
        #if DEBUG
        if isDemo { try? await Task.sleep(for:.milliseconds(700)); return }
        #endif
        await laundry.refresh(force:true); await laundry.refreshOrder()
    }

    /// Same sequence as 暖橙: re-read the machine, then ask for one explicit confirmation.
    private func order() {
        #if DEBUG
        if isDemo { sheet = confirmSheet(facts, newOrder:true); return }
        #endif
        preparing = true
        Task {
            await laundry.refresh(force:true)
            preparing = false
            let facts = LaundryFacts(model:laundry)
            guard laundry.mayCreate, selected(facts) != nil else { return }
            sheet = confirmSheet(facts, newOrder:true)
        }
    }

    /// 「核对洗衣订单」. Order 52: the model records 「已核对」 only when this re-check succeeded.
    private func check(failedStart: Bool) {
        Task {
            if isDemo { await reload(); return }
            if failedStart { await laundry.checkFailedOrder() } else { await reload() }
        }
    }

    private func submit(_ program: WasherProgram) {
        #if DEBUG
        if isDemo { runDemoBusy(); return }
        #endif
        if let device = laundry.snapshot?.deviceID {
            UserDefaults.standard.set(program.id, forKey:LaundryDetail.lastProgramKey(device))
        }
        submitting = true
        Task { await laundry.createAndPay(program); submitting = false }
    }

    private func payExisting() {
        #if DEBUG
        if isDemo { runDemoBusy(); return }
        #endif
        submitting = true
        Task { await laundry.pay(); submitting = false }
    }

    private func cancel() {
        #if DEBUG
        if isDemo { withAnimation(Theme.spring) { navigator.laundryDemo = LaundryDemo.make(.idle) }; return }
        #endif
        Task { await laundry.cancelOrder() }
    }

    private func resolve() {
        #if DEBUG
        if isDemo { withAnimation(Theme.spring) { navigator.laundryDemo = LaundryDemo.make(.idle) }; return }
        #endif
        Task { await laundry.resolveManually() }
    }

    #if DEBUG
    /// Fake progress only — never places an order.
    private func runDemoBusy() {
        let previous = navigator.laundryDemo
        Task {
            navigator.laundryDemo?.facts.busy = true; navigator.laundryDemo?.facts.mayCreate = false
            navigator.laundryDemo?.facts.progress = "正在下单…"
            try? await Task.sleep(for:.seconds(1.2))
            navigator.laundryDemo?.facts.progress = "正在打开支付宝…"
            try? await Task.sleep(for:.seconds(1.2))
            navigator.laundryDemo?.facts.progress = "正在核对订单…"
            try? await Task.sleep(for:.seconds(1.2))
            navigator.laundryDemo = previous
        }
    }
    #endif
}
