import SwiftUI
import Core

/// Laundry page: hero sentence + hairline lists + bottom dock, same skeleton as home.
/// All ordering/payment safety lives in `LaundryModel` / `LaundryCheckoutController`; this view only
/// decides what to show and forwards explicit user confirmations.
struct LaundryDetail: View {
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var reminders = Reminders.shared
    @State private var selectedId: Int?
    @State private var sheet: LaundrySheet?
    /// A confirmed create/pay sequence is running (covers the gap between its two steps).
    @State private var submitting = false
    /// Re-reading the machine right before the confirmation sheet.
    @State private var preparing = false
    #if DEBUG
    @State private var demo: LaundryDemo?
    init(demo: LaundryDemo? = nil) { _demo = State(initialValue:demo) }
    private var isDemo: Bool { demo != nil }
    #else
    init() {}
    private var isDemo: Bool { false }
    #endif

    private var facts: LaundryFacts {
        #if DEBUG
        if let demo { return demo.facts }
        #endif
        return LaundryFacts(model:laundry)
    }
    private var notifiesWhenDone: Bool {
        #if DEBUG
        if let demo { return demo.notify }
        #endif
        // Only promise 洗好了会通知你 when the reminder is on and notifications are allowed.
        return reminders.laundryDoneWillNotify
    }

    var body: some View {
        let facts = facts
        let phase = facts.phase()
        let busy = submitting || (facts.busy && Self.showsBusyDock(phase))
        ScrollView {
            VStack(alignment:.leading, spacing:0) {
                hero(facts, phase:phase)
                    .padding(.horizontal,24).padding(.top,20).padding(.bottom,6)
                below(facts, phase:phase, busy:busy)
            }
            .padding(.bottom,24)
            .frame(maxWidth:600)
            .frame(maxWidth:.infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("洗衣").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if Self.scanInToolbar(phase) {
                ToolbarItem(placement:.topBarTrailing) {
                    NavigationLink(value:HomeRoute.washerSetup) { Image(systemName:"qrcode.viewfinder") }
                        .accessibilityLabel("扫洗衣机")
                        .accessibilityIdentifier("laundryScan")
                }
            }
        }
        .safeAreaInset(edge:.bottom, spacing:0) { dock(facts, phase:phase, busy:busy) }
        // SwiftUI may cancel the pull's own task when the page changes under it (the read
        // starting does): the read runs on its own and the pull waits for it.
        .refreshable { await Task { await reload() }.value }
        .task {
            #if DEBUG
            if let initial = demo?.sheet {
                try? await Task.sleep(for:.milliseconds(450))
                sheet = initial == .cancel ? .cancel : confirmSheet(facts, newOrder:true)
                return
            }
            #endif
            guard !isDemo else { return }
            await laundry.refresh(); await laundry.refreshOrder()
        }
        // Unpaid reservation: re-read once the server's auto-cancel countdown passes (unchanged behaviour).
        .task(id:facts.record?.orderReadAt) {
            guard !isDemo, let record = facts.record, record.inFlight, let order = record.order,
                  order.status.code == "10", let seconds = order.countDown, seconds > 0 else { return }
            do { try await Task.sleep(for:.seconds(seconds + 1)) } catch { return }
            await laundry.refreshOrder()
        }
        // Running: the model reads the order a minute after the expected end (`syncActivity`).
        .sheet(item:$sheet) { item in sheetView(item, facts:facts).typesettingLanguage(Theme.typesetting) }
        // A lookup after the sheet came up (back from the U净 app) found something other than
        // no order: the clear is no longer allowed, so its sheet goes instead of doing nothing.
        .onChange(of:facts.record?.canResolveManually == true) { _, allowed in
            if !allowed, sheet == .resolve { sheet = nil }
        }
        .sensoryFeedback(.selection, trigger:selectedId)
    }

    /// Pages whose dock turns into the 「正在下单…」/「正在核对订单…」 progress pill while the model works.
    private static func showsBusyDock(_ phase: LaundryFacts.Phase) -> Bool {
        switch phase {
        case .idle, .done, .unpaid, .check: return true
        default: return false
        }
    }

    /// Scanning another washer lives on this page now that the home dock is gone. The pages
    /// whose dock already offers 扫洗衣机 (nothing bound, machine busy or unavailable) don't repeat it.
    static func scanInToolbar(_ phase: LaundryFacts.Phase) -> Bool {
        switch phase {
        case .empty, .inUse, .unavailable: return false
        default: return true
        }
    }

    // MARK: Hero

    private func hero(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> some View {
        VStack(alignment:.leading, spacing:0) { heroContent(facts, phase:phase) }
            .frame(maxWidth:.infinity, alignment:.leading)
    }

    @ViewBuilder private func heroContent(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> some View {
        switch phase {
        case .running(let end):
            LaundryRunHero(machine:facts.machine, program:facts.record?.programName ?? "洗衣",
                           minutes:facts.recordProgram?.time, end:end, notify:notifiesWhenDone)
            issues(facts, sub:nil)
        case .starting:
            VStack(alignment:.leading, spacing:0) {
                liveLabel("正在启动", machine:facts.machine)
                sentence([.init(text:"已付款，\n等机器启动。")]).padding(.top,8)
                issues(facts, sub:nil)
            }
        default:
            let copy = heroCopy(facts, phase:phase)
            VStack(alignment:.leading, spacing:0) {
                if let meta = meta(facts, phase:phase) {
                    Text(meta).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2).padding(.bottom,8)
                }
                sentence(copy.sentence)
                if let sub = copy.sub {
                    Text(sub).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2).lineSpacing(3)
                        .fixedSize(horizontal:false, vertical:true).padding(.top,10)
                }
                issues(facts, sub:copy.sub)
            }
            .frame(maxWidth:.infinity, alignment:.leading)
        }
    }

    private func liveLabel(_ text: String, machine: String?) -> some View {
        HStack(alignment:.firstTextBaseline, spacing:7) {
            PulseDot().alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
            Text([text, machine.map(LaundryFormat.machine)].compactMap { $0 }.joined(separator:" · "))
                .scaledFont(15, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.accentText)
        }
    }

    private func meta(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> String? {
        guard phase != .empty, let snapshot = facts.snapshot else { return nil }
        return [LaundryFormat.machine(snapshot.deviceNo), facts.store].compactMap { $0 }.joined(separator:" · ")
    }

    private func heroCopy(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> (sentence: [HomeData.Segment], sub: String?) {
        let machine = facts.snapshot.map { LaundryFormat.machine($0.deviceNo) } ?? "这台洗衣机"
        switch phase {
        case .empty:
            return ([.init(text:"扫一下洗衣机上的码，\n以后在这里就能下单。")], "对准机身上的二维码。")
        case .unknown:
            return ([.init(text:"还没读到洗衣机，\n下拉刷新一下。")], nil)
        case .idle, .done:
            return ([.init(text:"\(machine)空闲，\n放好衣服就能洗。")], nil)
        case .inUse:
            return ([.init(text:"\(machine)有人在用。")], "换一台，或者等会儿再来。")
        case .unavailable(let kind):
            let word = kind == .offline ? "离线了。" : kind == .broken ? "坏了。" : "停用了。"
            return ([.init(text:machine + word)], "换一台试试。")
        case .unpaid(let payable):
            let amount = facts.amount.map(Theme.yuan) ?? ""
            let sub = payable
                ? programLine(facts).map { $0 + "。付完款机器可能马上开始洗。" } ?? "付完款机器可能马上开始洗。"
                : "还没确认这笔付成功没有。先下拉刷新核对，别重复付款；确认没付成功，就取消订单重新下。"
            return ([.init(text:"还有一笔 "), .init(text:amount, color:Theme.accentLarge), .init(text:" 没付款。")], sub)
        case .check(let failedStart):
            if failedStart { return ([.init(text:"机器没启动。")], "去 U净 的订单里看看有没有扣款。") }
            return ([.init(text:"上次订单\n还没确认。")], "还没确认订单结果。先下拉刷新，别重复下单或付款。")
        case .running, .starting:
            return ([], nil)
        }
    }

    private func programLine(_ facts: LaundryFacts) -> String? {
        if let program = facts.recordProgram { return LaundryFormat.program(program) }
        return facts.record?.programName
    }

    private func sentence(_ segments: [HomeData.Segment]) -> some View {
        var text = AttributedString()
        for segment in segments {
            var run = AttributedString(segment.text)
            run.foregroundColor = segment.color ?? Theme.ink
            text += run
        }
        return Text(text)
            .scaledFont(30, .bold, relativeTo:.title)
            .tracking(-0.6).lineSpacing(5)
            .fixedSize(horizontal:false, vertical:true)
            .accessibilityAddTraits(.isHeader)
    }

    /// Error lines: gray with exclamationmark.circle, never orange/red. Cached data stays visible.
    @ViewBuilder private func issues(_ facts: LaundryFacts, sub: String?) -> some View {
        let lines = [facts.checkoutIssue, facts.issue, facts.outcomeNote()].compactMap { $0 }
            .reduce(into:[String]()) { list, line in if line != sub, !list.contains(line) { list.append(line) } }
        ForEach(lines, id:\.self) { line in
            Label {
                Text(line).fixedSize(horizontal:false, vertical:true)
            } icon: {
                Image(systemName:"exclamationmark.circle")
            }
            .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
            .padding(.top,10)
        }
    }

    // MARK: Below the hero

    @ViewBuilder private func below(_ facts: LaundryFacts, phase: LaundryFacts.Phase, busy: Bool) -> some View {
        switch phase {
        case .idle, .done:
            programList(facts, selectable:true, enabled:!busy && !preparing, dimmed:busy)
        case .inUse, .unavailable:
            programList(facts, selectable:false, enabled:false, dimmed:true)
        case .running, .starting:
            orderRows(facts, phase:phase)
        case .check:
            if let record = facts.record {
                HomeSectionHeader(text:"最近").padding(.top,30)
                RecentRow(item:RecentItem(id:"laundry-check", kind:.laundry, title:"洗衣 · " + record.programName,
                                          date:record.createdAt ?? Date(), detail:facts.machine.map(LaundryFormat.machine),
                                          amount:nil, source:.app),
                          accentWord:"待核对")
            }
        case .unpaid, .empty, .unknown:
            EmptyView()
        }
    }

    private func selected(_ facts: LaundryFacts) -> WasherProgram? {
        guard let programs = facts.snapshot?.programs else { return nil }
        if let selectedId, let match = programs.first(where:{ $0.id == selectedId }) { return match }
        if let device = facts.snapshot?.deviceID {
            let last = UserDefaults.standard.integer(forKey:Self.lastProgramKey(device))
            if let match = programs.first(where:{ $0.id == last }) { return match }
        }
        return programs.first
    }
    static func lastProgramKey(_ device: String) -> String { "laundryLastProgram." + device }

    @ViewBuilder private func programList(_ facts: LaundryFacts, selectable: Bool, enabled: Bool, dimmed: Bool) -> some View {
        if let programs = facts.snapshot?.programs, !programs.isEmpty {
            let chosen = selectable ? selected(facts)?.id : nil
            HomeSectionHeader(text:"选程序").padding(.top,30)
            VStack(spacing:0) {
                ForEach(Array(programs.enumerated()), id:\.element.id) { index, program in
                    if index > 0 { RowSeparator() }
                    LaundryProgramRow(program:program, selected:chosen == program.id) { selectedId = program.id }
                        .disabled(!enabled)
                        .opacity(dimmed ? 0.4 : 1)
                }
            }
        }
    }

    @ViewBuilder private func orderRows(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> some View {
        if let record = facts.record {
            HomeSectionHeader(text:"这笔订单").padding(.top,30)
            VStack(spacing:0) {
                StatusRow(symbol:"washer", title:programLine(facts) ?? record.programName,
                          subtitle:[facts.machine.map(LaundryFormat.machine), facts.store].compactMap { $0 }.joined(separator:" · "))
                    .accessibilityElement(children:.combine)
                if record.order?.paid == true {
                    RowSeparator()
                    // Payment channel is not in the order detail, so no 「支付宝」 subtitle.
                    StatusRow(symbol:"creditcard", title:"已付款", value:facts.amount.map { .amount(Theme.yuan($0)) })
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel(["已付款", facts.amount.map(LaundryFormat.spokenYuan)].compactMap { $0 }.joined(separator:"，"))
                }
            }
        }
    }

    // MARK: Dock

    @ViewBuilder private func dock(_ facts: LaundryFacts, phase: LaundryFacts.Phase, busy: Bool) -> some View {
        if busy {
            DockBar {
                DockPillLabel(title:facts.progress ?? (submitting ? "正在下单…" : "正在核对订单…"), style:.busy)
                    .accessibilityElement(children:.combine)
            }
        } else {
            idleDock(facts, phase:phase)
        }
    }

    @ViewBuilder private func idleDock(_ facts: LaundryFacts, phase: LaundryFacts.Phase) -> some View {
        switch phase {
        case .running, .starting, .unknown:
            EmptyView()
        case .idle, .done:
            let program = selected(facts)
            let title = "下单" + (program.map { " · " + Theme.yuan($0.price.yuan) } ?? "")
            DockBar {
                Button { order() } label: {
                    DockPillLabel(title:title, style:preparing ? .busy : (facts.mayCreate && program != nil ? .primary : .disabled))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!facts.mayCreate || preparing || program == nil)
                .accessibilityLabel(program.map { "下单，" + LaundryFormat.spokenYuan($0.price.yuan) } ?? "下单")
                .accessibilityIdentifier("reviewLaundryOrder")
            }
        case .unpaid(let payable):
            DockBar {
                if payable {
                    Button { sheet = confirmSheet(facts, newOrder:false) } label: {
                        DockPillLabel(title:"去付款" + (facts.amount.map { " " + Theme.yuan($0) } ?? ""),
                                      style:facts.busy ? .disabled : .primary)
                    }
                    .buttonStyle(PressScaleStyle()).disabled(facts.busy)
                } else {
                    checkButton(facts, failedStart:false)
                }
                if facts.mayCancel {
                    Button { sheet = .cancel } label: { DockRoundLabel(symbol:"xmark") }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("取消订单")
                        .accessibilityIdentifier("cancelLaundryOrder")
                }
            }
        case .check(let failedStart):
            DockBar {
                checkButton(facts, failedStart:failedStart)
                // The create's result is unknown and the check found nothing: once the user has
                // looked in the U净 app, the record can be cleared (it otherwise blocks laundry for good).
                if facts.record?.canResolveManually == true {
                    Button { sheet = .resolve } label: { DockRoundLabel(symbol:"xmark") }
                        .buttonStyle(PressScaleStyle()).disabled(facts.busy)
                        .accessibilityLabel("清除待核对的订单")
                        .accessibilityIdentifier("resolveLaundryOrder")
                }
            }
        case .inUse, .unavailable:
            DockBar {
                DockPillLabel(title:unavailableTitle(phase), style:.disabled)
                    .accessibilityElement(children:.combine).accessibilityAddTraits(.isStaticText)
                NavigationLink(value:HomeRoute.washerSetup) { DockRoundLabel(symbol:"qrcode.viewfinder") }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("扫另一台洗衣机")
            }
        case .empty:
            DockBar {
                NavigationLink(value:HomeRoute.washerSetup) { DockPillLabel(title:"扫洗衣机", symbol:"qrcode.viewfinder") }
                    .buttonStyle(PressScaleStyle())
            }
        }
    }

    private func unavailableTitle(_ phase: LaundryFacts.Phase) -> String {
        switch phase {
        case .unavailable(.offline): return "机器离线"
        case .unavailable(.broken): return "机器故障"
        case .unavailable(.disabled): return "机器停用"
        default: return "有人在用"
        }
    }

    private func checkButton(_ facts: LaundryFacts, failedStart: Bool) -> some View {
        Button {
            Task {
                #if DEBUG
                if demo != nil { await reload(); return }
                #endif
                // Order 52: the model records 「已核对」 only when this re-check actually succeeded.
                if failedStart { await laundry.checkFailedOrder() } else { await reload() }
            }
        } label: { DockPillLabel(title:"核对洗衣订单", style:facts.busy ? .disabled : .primary) }
            .buttonStyle(PressScaleStyle())
            .disabled(facts.busy)
    }

    // MARK: Actions

    private func reload() async {
        #if DEBUG
        if demo != nil { try? await Task.sleep(for:.milliseconds(700)); return }
        #endif
        await laundry.refresh(force:true); await laundry.refreshOrder()
    }

    /// Same sequence as before: re-read the machine, then ask for one explicit confirmation.
    private func order() {
        #if DEBUG
        if demo != nil { sheet = confirmSheet(facts, newOrder:true); return }
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
            let machine = facts.snapshot.map { LaundryFormat.machine($0.deviceNo) }
            let line = [machine, program.map(LaundryFormat.program) ?? programLine(facts)].compactMap { $0 }.joined(separator:" · ")
            LaundryPaySheet(title:newOrder ? "下单并去支付宝付款？" : "去支付宝付款？", line:line,
                            amount:program?.price.yuan ?? facts.amount) {
                sheet = nil
                if newOrder, let program { submit(program) } else { payExisting() }
            }
        case .cancel:
            LaundryCancelSheet {
                sheet = nil
                cancel()
            }
        case .resolve:
            LaundryResolveSheet {
                sheet = nil
                Task { await laundry.resolveManually() }
            }
        }
    }

    private func submit(_ program: WasherProgram) {
        #if DEBUG
        if demo != nil { runDemoBusy(); return }
        #endif
        if let device = laundry.snapshot?.deviceID { UserDefaults.standard.set(program.id, forKey:Self.lastProgramKey(device)) }
        submitting = true
        Task { await laundry.createAndPay(program); submitting = false }
    }

    private func payExisting() {
        #if DEBUG
        if demo != nil { runDemoBusy(); return }
        #endif
        submitting = true
        Task { await laundry.pay(); submitting = false }
    }

    private func cancel() {
        #if DEBUG
        if demo != nil { withAnimation(Theme.spring) { demo = LaundryDemo.make(.idle) }; return }
        #endif
        Task { await laundry.cancelOrder() }
    }

    #if DEBUG
    /// Fake progress only — never places an order.
    private func runDemoBusy() {
        let previous = demo
        Task {
            demo?.facts.busy = true; demo?.facts.mayCreate = false
            demo?.facts.progress = "正在下单…"
            try? await Task.sleep(for:.seconds(1.2))
            demo?.facts.progress = "正在打开支付宝…"
            try? await Task.sleep(for:.seconds(1.2))
            demo?.facts.progress = "正在核对订单…"
            try? await Task.sleep(for:.seconds(1.2))
            demo = previous
        }
    }
    #endif
}

enum LaundrySheet: Identifiable, Equatable {
    /// `program` for a new order; nil to pay the existing unpaid order.
    case confirm(program: WasherProgram?, newOrder: Bool)
    case cancel
    /// Clear an order whose creation was never confirmed (reconcile).
    case resolve
    var id: String {
        switch self {
        case .confirm(let program, let newOrder): return "confirm-\(newOrder)-\(program?.id ?? -1)"
        case .cancel: return "cancel"
        case .resolve: return "resolve"
        }
    }
    static func == (a: LaundrySheet, b: LaundrySheet) -> Bool { a.id == b.id }
}

// MARK: - Rows & hero

/// 「选程序」 row: selection mark · 「标准洗 · 45 分钟」 · price.
struct LaundryProgramRow: View {
    let program: WasherProgram
    let selected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Button(action:action) {
            HStack(alignment:typeSize.isAccessibilitySize ? .top : .center, spacing:14) {
                mark
                if typeSize.isAccessibilitySize {
                    VStack(alignment:.leading, spacing:6) { titles; price }
                    Spacer(minLength:0)
                } else {
                    titles
                    Spacer(minLength:8)
                    price
                }
            }
            .padding(.vertical,10).frame(minHeight:56)
            .padding(.horizontal,24)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("\(program.workModelName)，\(program.time) 分钟，\(LaundryFormat.spokenYuan(program.price.yuan))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
    private var mark: some View {
        ZStack {
            if selected {
                Circle().fill(Theme.accentText)
                Image(systemName:"checkmark").font(.system(size:13, weight:.bold)).foregroundStyle(Theme.accentInk)
            } else {
                Circle().strokeBorder(Theme.ink3, lineWidth:1.5)
            }
        }
        .frame(width:24, height:24)
    }
    private var titles: some View {
        VStack(alignment:.leading, spacing:2) {
            Text(LaundryFormat.program(program)).scaledFont(17, .medium).foregroundStyle(Theme.ink)
            if let note {
                Text(note).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                    .frame(maxWidth:typeSize.isAccessibilitySize ? nil : 200, alignment:.leading)
            }
        }.fixedSize(horizontal:false, vertical:true)
    }
    private var price: some View {
        Text(Theme.yuan(program.price.yuan)).scaledFont(20, .semibold, design:.rounded, relativeTo:.title3)
            .monospacedDigit().foregroundStyle(Theme.ink).lineLimit(1)
    }
    /// Note for the spin-only program (the machine's own description text is not decoded).
    private var note: String? { program.workModelName == "单脱水" ? "最多 3/4 桶，适合手洗的衣服甩干" : nil }
}

/// Running hero: live label · minutes left · progress line · sub.
struct LaundryRunHero: View {
    let machine: String?
    let program: String
    /// Program length in minutes, when the machine lists it (drives the progress line).
    let minutes: Int?
    let end: Date
    let notify: Bool
    var body: some View {
        TimelineView(minuteSchedule(to:end)) { context in
            let left = LaundryFormat.minutesLeft(until:end, now:context.date)
            VStack(alignment:.leading, spacing:0) {
                HStack(alignment:.firstTextBaseline, spacing:7) {
                    PulseDot().alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
                    Text(["正在洗衣", machine.map(LaundryFormat.machine)].compactMap { $0 }.joined(separator:" · "))
                        .scaledFont(15, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.accentText)
                }
                HStack(alignment:.firstTextBaseline, spacing:6) {
                    Text("\(left)")
                        .scaledFont(76, .semibold, design:.rounded, relativeTo:.largeTitle, cap:96)
                        .monospacedDigit().tracking(-2).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(countsDown:true))
                        .animation(.default, value:left)
                    Text("分钟").scaledFont(28, .semibold, relativeTo:.title).foregroundStyle(Theme.ink2)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top,6)
                if let minutes, minutes > 0 {
                    let total = Double(minutes * 60)
                    let fraction = min(1, max(0, 1 - end.timeIntervalSince(context.date) / total))
                    Capsule().fill(Theme.fill).frame(height:4)
                        .overlay(alignment:.leading) {
                            GeometryReader { proxy in
                                Capsule().fill(Theme.accent).frame(width:proxy.size.width * fraction)
                            }
                        }
                        .padding(.top,16)
                }
                Text(program + " · " + CampusFormat.clock(end) + " 洗完。" + (notify ? "洗好了会通知你。" : ""))
                    .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2).lineSpacing(3)
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.top,10)
            }
            .frame(maxWidth:.infinity, alignment:.leading)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(["正在洗衣", machine.map(LaundryFormat.machine), "还剩 \(left) 分钟",
                                 LaundryFormat.spokenClock(end) + "洗完"].compactMap { $0 }.joined(separator:"，"))
        }
    }
}

// MARK: - Sheets

/// One confirmation before any order or payment request (replaces the old review sheet + Alipay alert).
private struct LaundryPaySheet: View {
    let title: String
    let line: String
    let amount: Decimal?
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false
    var body: some View {
        LaundrySheetBody(height:360) {
            Text(title).scaledFont(24, .bold, relativeTo:.title2).foregroundStyle(Theme.ink)
                .fixedSize(horizontal:false, vertical:true)
            Text(line).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2).padding(.top,14)
            if let amount {
                Text(Theme.yuan(amount)).scaledFont(44, .semibold, design:.rounded, relativeTo:.largeTitle)
                    .monospacedDigit().tracking(-1).foregroundStyle(Theme.ink).padding(.top,2)
            }
            Text("付完款机器可能马上开始洗，先把衣服放好。实际金额以支付宝里显示的为准。")
                .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2).lineSpacing(4)
                .fixedSize(horizontal:false, vertical:true).padding(.top,14)
            Button { submitted = true; confirm() } label: { DockPillLabel(title:"去付款") }
                .buttonStyle(PressScaleStyle()).disabled(submitted)
                .padding(.top,24)
                .accessibilityIdentifier("submitLaundryOrder")
            Button { dismiss() } label: {
                Text("先不付").scaledFont(17, .medium).foregroundStyle(Theme.ink2)
                    .frame(maxWidth:.infinity).frame(minHeight:50).contentShape(Rectangle())
            }.buttonStyle(RowPressStyle())
        }
    }
}

private struct LaundryCancelSheet: View {
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false
    var body: some View {
        LaundrySheetBody(height:280) {
            Text("取消这笔订单？").scaledFont(24, .bold, relativeTo:.title2).foregroundStyle(Theme.ink)
            Text("只能取消还没付款的订单，取消后这台机器会让给别人。")
                .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2).lineSpacing(4)
                .fixedSize(horizontal:false, vertical:true).padding(.top,14)
            Button { submitted = true; confirm() } label: { DockPillLabel(title:"取消订单", style:.destructive) }
                .buttonStyle(PressScaleStyle()).disabled(submitted)
                .padding(.top,24)
                .accessibilityIdentifier("confirmCancelLaundryOrder")
            Button { dismiss() } label: {
                Text("留着").scaledFont(17, .medium).foregroundStyle(Theme.ink2)
                    .frame(maxWidth:.infinity).frame(minHeight:50).contentShape(Rectangle())
            }.buttonStyle(RowPressStyle())
        }
    }
}

/// Clearing a record whose order U净 never showed: only after the user looked in the U净 app.
private struct LaundryResolveSheet: View {
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false
    var body: some View {
        LaundrySheetBody(height:300) {
            Text("清除这笔待核对的订单？").scaledFont(24, .bold, relativeTo:.title2).foregroundStyle(Theme.ink)
                .fixedSize(horizontal:false, vertical:true)
            Text("先去 U净 App 的订单里看看。没有这笔订单再清除；有的话，在 U净 App 里处理。")
                .scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2).lineSpacing(4)
                .fixedSize(horizontal:false, vertical:true).padding(.top,14)
            Button { submitted = true; confirm() } label: { DockPillLabel(title:"没有订单，清除", style:.destructive) }
                .buttonStyle(PressScaleStyle()).disabled(submitted)
                .padding(.top,24)
                .accessibilityIdentifier("confirmResolveLaundryOrder")
            Button { dismiss() } label: {
                Text("留着").scaledFont(17, .medium).foregroundStyle(Theme.ink2)
                    .frame(maxWidth:.infinity).frame(minHeight:50).contentShape(Rectangle())
            }.buttonStyle(RowPressStyle())
        }
    }
}

/// Sheet chrome: `group` background, drag indicator, ≈height detent + large, scrolls at large text.
private struct LaundrySheetBody<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:0) { content }
                .padding(.horizontal,24).padding(.top,30).padding(.bottom,12)
                .frame(maxWidth:.infinity, alignment:.leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.group)
    }
}
