import SwiftUI
import Core

/// Copy for the shower page.
enum ShowerPageText {
    static let steps = ["连接", "出水", "结算"]
    static let connecting = "正在连接水控…"
    static let connectingBody = "站近一点，蓝牙别关。"
    static let runningLabel = "正在洗澡"
    static let runningBody = "按水控上的出水键就有热水。洗完点「结束并结算」，或者直接在水控上按停。"
    static let runningNote = "锁屏或灵动岛上也能结束并结算。"
    /// Under 结束并结算 from its tap until the settlement is done (instead of `runningNote`).
    static let endingNote = "结算完成前，先别离开水控。"
    static let settling = "正在结算…"
    static let settlingBody = "先别离开水控。"
    static let doneLabel = "洗好了"
    static let connectFailed = "没连上水控"
    static let connectFailedBody = "站近一点，确认蓝牙开着，再试一次。"
    static let denied = ShowerAuthorizeRefusedText.title
    static let deniedBody = "这次没扣钱。过一会儿再试，一直这样就去学校的热水记录里看看。"
    static let inUse = "水控有人在用"
    static let inUseBody = "附近的水控有人在用，现在开不了水。等它空了再试。这次没扣钱。"
    /// The ready layout's headline (the 热水洗澡 screen's).
    static let readyTitle = "准备洗澡"
    /// The shower is over (stopped on the controller, or kept with its outcome unknown): the product
    /// copy, kept in `ShowerAuthorText`.
    static let stoppedTitle = ShowerAuthorText.stoppedTitle
    /// The page's one button then.
    static let startNext = ShowerAuthorText.startNext
    /// The one line under it, for one or many such showers.
    static let stoppedNote = ShowerAuthorText.stoppedNote
    /// The stopped page once the next start (or 再查一次) found the controller in use (title `inUse`).
    static let checkInUseBody = "水控显示正在用水，现在开不了新的一次。如果是你没停的水，先在水控上按停，再点「再查一次」。"
    /// That page's one button.
    static let recheckInUse = "再查一次"
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
        // The page itself says 水控有人在用; this is what VoiceOver hears.
        case .inUse: return inUse + "。" + checkInUseBody
        }
    }
    /// The way out of a saved record that can't be read, and its confirmation.
    static let unreadableClear = "清除这条记录"
    static let unreadableClearConfirm = "清除这条记录？"
    static let unreadableClearNote = "先去学校的热水记录里看看这次扣了没有。清除以后，校日常不会再结算这一次。"
    static let unreadableClearButton = "看过了，清除"
    static let unreadableKeep = "留着"

    /// Above 结束并结算 when the last end came back to the timer.
    /// 结束 found the controller running someone else's session: no close was sent.
    static let endInUseByOther = "水控有人在用，没发结束，免得关掉别人的水。"
    static func endFailed(_ failure: ShowerEndFailure) -> String {
        switch failure {
        case .noConnection: return "没连上水控，还没结束。靠近一点再点一次。"
        case .wrongController: return "连到的不是这间的水控，还没结束。再点一次。"
        case .notSent: return "还没发出去，没结束。再点一次。"
        case .inUseByOther: return endInUseByOther
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
    @Environment(\.appTheme) private var appTheme
    @EnvironmentObject private var shower: ShowerModel
    let room: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @State private var successTick = 0
    @State private var errorTick = 0
    @State private var pulse = false

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
            // Stopped on the controller: this shower is over, not a failure.
            case .done?, .stopped?: successTick += 1
            case .connectFailed?, .denied?: errorTick += 1
            default: break
            }
            if let phase { AccessibilityNotification.Announcement(announcement(phase)).post() }
        }
        .onChange(of:flow.recheckResult) { _, result in
            guard let result else { return }
            AccessibilityNotification.Announcement(ShowerPageText.recheckResult(result)).post()
        }
        .onChange(of:flow.foundInUse) { _, inUse in
            // 再查一次 says it with its result.
            guard inUse, flow.recheckResult != .inUse else { return }
            errorTick += 1
            AccessibilityNotification.Announcement(ShowerPageText.inUse + "。" + ShowerPageText.checkInUseBody).post()
        }
        .onChange(of:flow.endFailed) { _, failure in
            guard let failure else { return }
            errorTick += 1
            AccessibilityNotification.Announcement(ShowerPageText.endFailed(failure)).post()
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
                } else if phase == .stopped {
                    circleButton("chevron.down", label:"收起") { shower.pageEvent(.collapseTapped) }
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
                    Text("¥" + amount.yuanText).scaledFont(64, .semibold, design:appTheme.numberDesign, relativeTo:.largeTitle, cap:96)
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
            case .stopped:
                if flow.foundInUse {
                    // The next start (or 再查一次) found water running: the in-use page.
                    icon("lock.slash", Theme.ink2)
                    title(ShowerPageText.inUse)
                    bodyText(ShowerPageText.checkInUseBody)
                } else {
                    // Over: the start layout with its own headline, no timer, nothing to alarm.
                    title(ShowerPageText.stoppedTitle)
                }
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
            .scaledFont(88, .semibold, design:appTheme.numberDesign, relativeTo:.largeTitle, cap:112)
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

    private func icon(_ symbol: String, _ color: ThemeColor) -> some View {
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
            case .running, .stopped:
                stepBottom(stopped:page?.phase == .stopped)
            case .settling:
                HStack(spacing:8) {
                    ProgressView().tint(Theme.ink2)
                    Text(ShowerPageText.settling).scaledFont(17, .semibold, relativeTo:.headline).foregroundStyle(Theme.ink2)
                }
                .frame(maxWidth:.infinity).frame(minHeight:60)
                .background(Theme.fill, in:appTheme.buttonShape.shape)
                .accessibilityElement(children:.combine)
                footnote(ShowerPageText.endingNote).padding(.top,6)
            case .done:
                capsule("好", background:Theme.pill, ink:Theme.pillInk) { shower.pageEvent(.closeTapped) }
            case .denied:
                capsule("好", background:Theme.pill, ink:Theme.pillInk) { shower.pageEvent(.closeTapped) }
            case .connectFailed:
                capsule("再试一次", background:Theme.pill, ink:Theme.pillInk, enabled:!flow.starting) { shower.pageEvent(.retryTapped) }
                textButton("取消") { shower.pageEvent(.closeTapped) }
            }
        }
        .animation(.easeInOut(duration:0.2), value:page?.phase)
    }

    /// 清爽's accent is the same blue in dark mode: white on it in both.
    private var accentInk: ThemeColor {
        appTheme == .clear ? Theme.accentInk : .fixed(scheme == .dark ? Color(white:0.07) : .white)
    }

    /// The page's one button is the next step: 结束并结算 while water runs, 开始下一次洗澡 once
    /// the shower is over (the same button, its words cross-fading). Under it the running line
    /// (「结算完成前，先别离开水控。」 from the tap of 结束 until the settlement is done), or once
    /// over the one line. Over and found in use: only 再查一次.
    @ViewBuilder private func stepBottom(stopped: Bool) -> some View {
        if stopped, flow.foundInUse {
            capsule(flow.rechecking ? ShowerPageText.rechecking : ShowerPageText.recheckInUse,
                    background:Theme.pill, ink:Theme.pillInk, enabled:flow.mayRecheck) { shower.pageEvent(.recheckTapped) }
                .accessibilityIdentifier("showerRecheck")
        } else {
            // No platform profile: 结束 would close the water with no way to settle it.
            if let line = stopped ? (flow.nextFailed ? shower.message : nil)
                : shower.platformMissing ? ShowerModel.platformMissingText : flow.endFailed.map(ShowerPageText.endFailed) {
                noticeLine(line)
            }
            capsule(stopped ? ShowerPageText.startNext : "结束并结算", background:Theme.accent, ink:accentInk,
                    enabled:stopped ? flow.mayStartNext && shower.mayStartNext : flow.mayEnd && !shower.platformMissing) {
                shower.pageEvent(stopped ? .startNextTapped : .endTapped)
            }
            .accessibilityIdentifier(stopped ? "showerStartNext" : "showerEnd")
            if stopped {
                footnote(ShowerPageText.stoppedNote).padding(.top,6)
                    .accessibilityIdentifier("showerStoppedNote")
            } else if flow.endFailed == nil && !shower.platformMissing {
                // The end-failed line takes its place while shown.
                footnote(flow.ending ? ShowerPageText.endingNote : ShowerPageText.runningNote).padding(.top,6)
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
            .multilineTextAlignment(.center).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal:false, vertical:true)
            .frame(maxWidth:.infinity)
    }

    private func noticeLine(_ line: String) -> some View {
        HStack(alignment:.firstTextBaseline, spacing:6) {
            Image(systemName:"exclamationmark.circle.fill").scaledFont(17, relativeTo:.body).accessibilityHidden(true)
            Text(line).scaledFont(15, relativeTo:.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal:false, vertical:true)
        }
        .foregroundStyle(Theme.notice)
        .frame(maxWidth:.infinity, alignment:.leading)
        .padding(.bottom,6)
        .accessibilityElement(children:.combine)
    }

    /// Disabled: the app's standard disabled pill (fill + ink3), as on the login button.
    private func capsule(_ label: String, background: ThemeColor, ink: ThemeColor, enabled: Bool = true,
                         action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Text(label).scaledFont(18, .semibold, relativeTo:.headline).foregroundStyle(enabled ? ink : Theme.ink3)
                .contentTransition(.opacity)
                .frame(maxWidth:.infinity).frame(minHeight:60)
                .background(enabled ? background : Theme.fill, in:appTheme.buttonShape.shape)
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
        case .stopped: return flow.foundInUse ? ShowerPageText.inUse : ShowerPageText.stoppedTitle
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

    private func bar(_ mark: ShowerStepMark) -> ThemeColor {
        switch mark {
        case .done: return Theme.ink
        case .current: return Theme.accent
        case .failed: return Theme.ink2
        case .future: return Theme.fill
        }
    }

    private func label(_ mark: ShowerStepMark) -> ThemeColor {
        switch mark {
        case .done: return Theme.ink2
        case .current, .failed: return Theme.ink
        case .future: return Theme.ink2
        }
    }
}
