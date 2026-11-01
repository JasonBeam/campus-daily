import SwiftUI
import Core

/// Copy for the shower page.
enum ShowerPageText {
    static let steps = ["连接", "出水", "结算"]
    static let connecting = "正在连接水控…"
    static let connectingBody = "站近一点，蓝牙别关。"
    static let runningLabel = "正在洗澡"
    static let runningBody = "按水控上的出水键就有热水，结算后显示费用。"
    static let runningNote = "锁屏或灵动岛上也能结束并结算。"
    static let settling = "正在结算…"
    static let settlingBody = "先别离开水控。"
    static let doneLabel = "洗好了"
    static let connectFailed = "没连上水控"
    static let connectFailedBody = "站近一点，确认蓝牙开着，再试一次。"
    static let denied = "水控没让开水"
    static let deniedBody = "这次没扣钱。过一会儿再试，一直这样就去学校的热水记录里看看。"
    static let inUse = "水控有人在用"
    static let inUseBody = "附近的水控有人在用，现在开不了水。等它空了再试。这次没扣钱。"
    static let unsure = "不确定结算了没有"
    static let unsureBody = "别再点结算，免得重复扣钱。核对一下学校那边这次扣了没有。"
    static let check = "这次洗澡要核对一下"
    static let checkBody = "水控显示已经停了，但这次还没结算上。去学校的热水记录里看看扣了没有，核对完才能再洗。"
    /// The home button while that check waits.
    static let checkButton = "核对上次洗澡"
    static let review = "去核对"
    static let resolve = "我在学校记录里核对过了"
    /// The needs-check face's read-only probe, under the body.
    static let recheck = "再查一次水控"
    static let rechecking = "正在查水控…"
    static let bluetoothOff = "蓝牙关着，打开后再核对。"
    static func recheckResult(_ result: ShowerRecheckResult) -> String {
        switch result {
        case .stopped: return "查过了，水控是停着的。"
        case .noConnection: return "没连上水控，靠近一点再查。"
        case .otherController: return "附近的水控不是你宿舍的那台。"
        case .bluetoothOff: return bluetoothOff
        case .busy: return SchoolLoginText.busy
        case .failed: return "没查到水控，再试一次。"
        case .unavailable: return "现在查不了，等一下再试。"
        }
    }
    static let resolveConfirm = "这次洗澡核对过了吗？"
    static let resolveConfirmButton = "核对过了"
    static let resolveConfirmNote = "标记以后，校日常不会再结算这一次。先在学校的热水记录里找到这次洗澡，再点核对过了。"

    /// Above 结束并结算 when the last end came back to the timer.
    static func endFailed(_ failure: ShowerEndFailure) -> String {
        switch failure {
        case .noConnection: return "没连上水控，还没结束。靠近一点再点一次。"
        case .wrongController: return "连到的不是这间的水控，还没结束。再点一次。"
        case .notSent: return "还没发出去，没结束。再点一次。"
        case .other: return "没结束，水可能还在出。再点一次。"
        }
    }

    static func doneBody(minutes: Int?) -> String {
        guard let minutes else { return "看一眼水停了没。" }
        return "这次 \(minutes) 分钟。看一眼水停了没。"
    }

    /// 「已经洗了 8 分 42 秒」, rounded down to 30 s so VoiceOver isn't flooded.
    static func elapsed(since start: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)) / 30 * 30)
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        var text = "已经洗了 "
        if h > 0 { text += "\(h) 小时 " }
        text += "\(m) 分"
        if s > 0 { text += " \(s) 秒" }
        return text
    }
}

/// The full-screen shower page: connect → water → settle → result, and the three failures,
/// in one view that changes in place.
struct ShowerPageView: View {
    @EnvironmentObject private var shower: ShowerModel
    let room: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @State private var successTick = 0
    @State private var errorTick = 0
    @State private var pulse = false
    @State private var confirmResolve = false

    private var flow: ShowerPageFlow { shower.page }

    var body: some View {
        let page = flow.page
        VStack(alignment:.leading, spacing:0) {
            topBar(page?.phase)
            if let page { StepBar(steps:page.steps, number:page.stepNumber).padding(.top,24) }
            if typeSize.isAccessibilitySize {
                // Large text: the face and its buttons scroll rather than squeeze or cut lines.
                ScrollView {
                    VStack(alignment:.leading, spacing:0) {
                        face(page).padding(.top,32)
                        bottom(page).padding(.top,32)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                face(page).padding(.top,68)
                Spacer(minLength:24)
                bottom(page)
            }
        }
        .padding(.horizontal,24)
        .padding(.bottom,20)
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
        .background(Theme.bg.ignoresSafeArea())
        .animation(reduceMotion ? .easeInOut(duration:0.2) : Theme.spring, value:page?.phase)
        .interactiveDismissDisabled(!flow.mayCollapse)
        .sensoryFeedback(.success, trigger:successTick)
        .sensoryFeedback(.error, trigger:errorTick)
        .onChange(of:page?.phase) { _, phase in
            switch phase {
            case .done?: successTick += 1
            case .connectFailed?, .denied?, .unsure?, .needsCheck?: errorTick += 1
            default: break
            }
            if let phase { AccessibilityNotification.Announcement(announcement(phase)).post() }
        }
        .onChange(of:flow.recheckResult) { _, result in
            guard let result else { return }
            AccessibilityNotification.Announcement(ShowerPageText.recheckResult(result)).post()
        }
        .onChange(of:flow.endFailed) { _, failure in
            guard let failure else { return }
            errorTick += 1
            AccessibilityNotification.Announcement(ShowerPageText.endFailed(failure)).post()
        }
        .confirmationDialog(ShowerPageText.resolveConfirm, isPresented:$confirmResolve, titleVisibility:.visible) {
            Button(ShowerPageText.resolveConfirmButton) { shower.pageEvent(.resolveTapped) }
            Button("取消", role:.cancel) {}
        } message: {
            Text(ShowerPageText.resolveConfirmNote)
        }
        .typesettingLanguage(Theme.typesetting)
    }

    private func face(_ page: ShowerPage?) -> some View {
        main(page)
            .id(page?.phase)
            .transition(reduceMotion ? .opacity : .opacity.combined(with:.offset(y:6)))
    }

    // MARK: Top bar

    private func topBar(_ phase: ShowerPagePhase?) -> some View {
        ZStack {
            Text(Theme.dorm(room).map { "热水 · \($0)" } ?? "热水").scaledFont(15, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1).multilineTextAlignment(.center)
                .fixedSize(horizontal:false, vertical:true).padding(.horizontal,48)
            HStack {
                if phase == .running {
                    circleButton("chevron.down", label:"收起，继续洗澡") { shower.pageEvent(.collapseTapped) }
                } else if phase == .connectFailed {
                    circleButton("xmark", label:"关闭") { shower.pageEvent(.closeTapped) }
                }
                Spacer()
            }
        }
        .frame(minHeight:38)
        .padding(.top,14)
        .accessibilitySortPriority(-1)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        let button = Button(action:action) {
            Image(systemName:symbol).font(.system(size:16, weight:.semibold)).foregroundStyle(Theme.ink)
                .frame(width:44, height:44)
        }
        .accessibilityLabel(label)
        return button.background(.ultraThinMaterial, in:Circle()).frame(width:44, height:44)
    }

    // MARK: Main block

    @ViewBuilder private func main(_ page: ShowerPage?) -> some View {
        VStack(alignment:.leading, spacing:0) {
            switch page?.phase ?? .connecting {
            case .connecting:
                ProgressView().controlSize(.large).tint(Theme.ink2).frame(height:34).padding(.bottom,18)
                    .accessibilityHidden(true)
                title(ShowerPageText.connecting)
                bodyText(ShowerPageText.connectingBody)
            case .running:
                runningLabel.padding(.bottom,10)
                timer(page?.startedAt)
                bodyText(page?.writeUnconfirmed == true ? ShowerDisplay.writeUnconfirmedHint + "。" : ShowerPageText.runningBody)
            case .settling:
                ProgressView().controlSize(.large).tint(Theme.ink2).frame(height:34).padding(.bottom,18)
                    .accessibilityHidden(true)
                title(ShowerPageText.settling)
                bodyText(ShowerPageText.settlingBody)
            case .done:
                Mascot(size:64).accessibilityHidden(true)
                Text(ShowerPageText.doneLabel).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2).padding(.top,10)
                if let amount = page?.amount {
                    // Only the platform's amount is ever shown.
                    Text("¥" + amount.yuanText).scaledFont(64, .semibold, design:.rounded, relativeTo:.largeTitle, cap:96)
                        .monospacedDigit().tracking(-2).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.top,4)
                        .accessibilityLabel("这次 \(amount.yuanText) 元")
                }
                bodyText(ShowerPageText.doneBody(minutes:page?.minutes))
            case .connectFailed:
                icon("antenna.radiowaves.left.and.right.slash", Theme.ink2)
                title(ShowerPageText.connectFailed)
                bodyText(ShowerPageText.connectFailedBody)
            case .denied:
                icon("lock.slash", Theme.ink2)
                if page?.denial == .inUse {
                    title(ShowerPageText.inUse)
                    bodyText(ShowerPageText.inUseBody)
                } else {
                    title(ShowerPageText.denied)
                    bodyText(ShowerPageText.deniedBody)
                }
            case .unsure:
                icon("questionmark.circle", Theme.accentText)
                title(ShowerPageText.unsure)
                bodyText(ShowerPageText.unsureBody)
            case .needsCheck:
                icon("questionmark.circle", Theme.accentText)
                title(ShowerPageText.check)
                bodyText(ShowerPageText.checkBody)
                ShowerRecheckRow().padding(.top,18)
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }

    private var runningLabel: some View {
        HStack(spacing:8) {
            Circle().fill(Theme.accent).frame(width:8, height:8)
                .opacity(pulse ? 0.35 : 1)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration:0.9).repeatForever(autoreverses:true)) { pulse = true }
                }
                .accessibilityHidden(true)
            Text(ShowerPageText.runningLabel).scaledFont(15, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.accentText)
        }
    }

    @ViewBuilder private func timer(_ start: Date?) -> some View {
        let start = start ?? Date()
        Text(timerInterval:start...Date.distantFuture, countsDown:false)
            .scaledFont(88, .semibold, design:.rounded, relativeTo:.largeTitle, cap:112)
            .monospacedDigit().tracking(-3).foregroundStyle(Theme.ink)
            .lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityHidden(true)
            .overlay {
                // VoiceOver reads the elapsed time in words, refreshed at most every 30 s.
                TimelineView(.periodic(from:start, by:30)) { context in
                    Color.clear.accessibilityElement()
                        .accessibilityLabel(ShowerPageText.elapsed(since:start, now:context.date))
                }
            }
    }

    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName:symbol).font(.system(size:30, weight:.regular)).foregroundStyle(color)
            .frame(height:34).padding(.bottom,18).accessibilityHidden(true)
    }

    private func title(_ text: String) -> some View {
        Text(text).scaledFont(34, .bold, relativeTo:.largeTitle).tracking(-0.7).foregroundStyle(Theme.ink)
            .fixedSize(horizontal:false, vertical:true)
            .accessibilityAddTraits(.isHeader)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text).scaledFont(17, relativeTo:.body).foregroundStyle(Theme.ink2).lineSpacing(6)
            .frame(maxWidth:330, alignment:.leading)
            .fixedSize(horizontal:false, vertical:true)
            .padding(.top,14)
    }

    // MARK: Bottom block

    @ViewBuilder private func bottom(_ page: ShowerPage?) -> some View {
        VStack(spacing:6) {
            switch page?.phase ?? .connecting {
            case .connecting:
                capsule("取消", background:Theme.fill, ink:Theme.ink, enabled:flow.mayCancel) { shower.pageEvent(.cancelTapped) }
            case .running:
                if let failure = flow.endFailed {
                    HStack(alignment:.firstTextBaseline, spacing:6) {
                        Image(systemName:"exclamationmark.circle.fill").scaledFont(17, relativeTo:.body).accessibilityHidden(true)
                        Text(ShowerPageText.endFailed(failure)).scaledFont(15, relativeTo:.subheadline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal:false, vertical:true)
                    }
                    .foregroundStyle(Theme.accentText)
                    // From the capsule's left edge across its width, 12 pt above it.
                    .frame(maxWidth:.infinity, alignment:.leading)
                    .padding(.bottom,6)
                    .accessibilityElement(children:.combine)
                }
                capsule("结束并结算", background:Theme.accent, ink:scheme == .dark ? Color(white:0.07) : .white,
                        enabled:flow.mayEnd) { shower.pageEvent(.endTapped) }
                // The end-failed line takes its place while shown.
                if flow.endFailed == nil {
                    Text(ShowerPageText.runningNote).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center).padding(.top,6)
                }
            case .settling:
                HStack(spacing:8) {
                    ProgressView().tint(Theme.ink2)
                    Text(ShowerPageText.settling).scaledFont(17, .semibold, relativeTo:.headline).foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth:.infinity).frame(minHeight:60)
                .background(Theme.fill, in:Capsule())
                .accessibilityElement(children:.combine)
            case .done:
                capsule("好", background:Theme.pill, ink:Theme.pillInk) { shower.pageEvent(.closeTapped) }
            case .denied:
                capsule("好", background:Theme.pill, ink:Theme.pillInk) { shower.pageEvent(.closeTapped) }
            case .connectFailed:
                capsule("再试一次", background:Theme.pill, ink:Theme.pillInk, enabled:!flow.starting) { shower.pageEvent(.retryTapped) }
                textButton("取消") { shower.pageEvent(.closeTapped) }
            case .unsure:
                capsule(ShowerPageText.review, background:Theme.pill, ink:Theme.pillInk) { shower.pageEvent(.reviewTapped) }
                textButton("先回首页") { shower.pageEvent(.homeTapped) }
            case .needsCheck:
                capsule(ShowerPageText.review, background:Theme.pill, ink:Theme.pillInk, enabled:!flow.rechecking) {
                    shower.pageEvent(.reviewTapped)
                }
                textButton(ShowerPageText.resolve) { confirmResolve = true }
                    .disabled(!flow.mayResolve).opacity(flow.mayResolve ? 1 : 0.5)
            }
        }
    }

    /// Disabled: the app's standard disabled pill (fill + ink3), as on the login button.
    private func capsule(_ label: String, background: Color, ink: Color, enabled: Bool = true,
                         action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Text(label).scaledFont(18, .semibold, relativeTo:.headline).foregroundStyle(enabled ? ink : Theme.ink3)
                .frame(maxWidth:.infinity).frame(minHeight:60)
                .background(enabled ? background : Theme.fill, in:Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }

    private func textButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Text(label).scaledFont(17, .medium, relativeTo:.body).foregroundStyle(Theme.ink2)
                .frame(maxWidth:.infinity).frame(minHeight:50)
        }
        .buttonStyle(RowPressStyle())
    }

    private func announcement(_ phase: ShowerPagePhase) -> String {
        switch phase {
        case .connecting: return ShowerPageText.connecting
        case .running: return ShowerPageText.runningLabel
        case .settling: return ShowerPageText.settling
        case .done: return ShowerPageText.doneLabel
        case .connectFailed: return ShowerPageText.connectFailed
        case .denied: return flow.page?.denial == .inUse ? ShowerPageText.inUse : ShowerPageText.denied
        case .unsure: return ShowerPageText.unsure
        case .needsCheck: return ShowerPageText.check
        }
    }
}

/// 连接 · 出水 · 结算: three bars with their labels, read as one element.
private struct StepBar: View {
    let steps: [ShowerStepMark]
    let number: Int
    var body: some View {
        HStack(alignment:.top, spacing:8) {
            ForEach(Array(steps.enumerated()), id:\.offset) { index, mark in
                VStack(alignment:.leading, spacing:8) {
                    Capsule().fill(bar(mark)).frame(height:4)
                    Text(ShowerPageText.steps[index]).scaledFont(13, .semibold, relativeTo:.footnote)
                        .foregroundStyle(label(mark)).lineLimit(1)
                }
                .frame(maxWidth:.infinity, alignment:.leading)
            }
        }
        .animation(.easeInOut(duration:0.3), value:steps)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("第 \(number) 步，共 3 步，\(ShowerPageText.steps[min(max(number - 1, 0), 2)])")
    }

    private func bar(_ mark: ShowerStepMark) -> Color {
        switch mark {
        case .done: return Theme.ink
        case .current: return Theme.accent
        case .failed: return Theme.ink2
        case .future: return Theme.fill
        }
    }

    private func label(_ mark: ShowerStepMark) -> Color {
        switch mark {
        case .done: return Theme.ink2
        case .current, .failed: return Theme.ink
        case .future: return Theme.ink3
        }
    }
}
