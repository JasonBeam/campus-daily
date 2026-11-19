import SwiftUI
import Core

/// First-run guide, presented as a full-screen cover: 登录 → 宿舍 → 好了. Laundry is not asked: it
/// is on unless the 学校洗衣机 switch in 设置 says otherwise. The controller is not checked here
/// but at the first 开始洗澡 (`doneNote` says so). 「先不设置」 closes it from 登录 and 宿舍.
struct OnboardingView: View {
    @Environment(\.appTheme) private var appTheme
    enum Step: Int, CaseIterable { case login, dorm, done }
    /// Page dots: 选样子 (「选一个样子」, before the guide), 登录, 宿舍; 好了 has none.
    static let dotted = 3

    /// The dot of a step: 选样子 is the first, so 登录 is the second.
    static func dot(_ step: Step) -> Int { step.rawValue + 1 }

    /// VoiceOver for the page dots.
    static func dotsLabel(_ step: Step) -> String { "第 \(dot(step) + 1) 步，共 \(dotted) 步" }
    /// 好了's card: the controller is checked at the first 开始洗澡.
    static let doneNote = "第一次洗澡时，站在水控旁边点开始，会先核对是不是你宿舍的水控。"
    /// Top right on 登录 and 宿舍: closes the guide, seen (as 清爽's 稍后设置).
    static let skip = "先不设置"

    #if DEBUG
    /// DEBUG demo values (`App/Demo`); when set, no real login or picker is opened.
    var preview: Preview?
    #endif
    var close: () -> Void
    /// Told each step the guide moves to, so a link asking for another one can send it there
    /// (`GuideRequest.moved(to:)`).
    private var moved: (Step) -> Void = { _ in }

    /// `moved` is told each step the guide moves to.
    func onStep(_ moved: @escaping (Step) -> Void) -> Self {
        var copy = self; copy.moved = moved; return copy
    }

    #if DEBUG
    init(start: Step = .login, preview: Preview? = nil, close: @escaping () -> Void) {
        self.preview = preview; self.close = close
        _step = State(initialValue:start)
        let typed = preview?.saved?.account ?? preview?.account ?? ""
        _account = State(initialValue:typed)
        _password = State(initialValue:preview?.password ?? "")
        _savePassword = State(initialValue:preview?.saved.map { SchoolAccount.savesPasswordByDefault($0, typed:typed) }
                              ?? preview?.savePassword ?? false)
        _loginState = State(initialValue:preview?.loginState ?? .idle)
        _apartment = State(initialValue:preview?.picked)
        _meterAsked = State(initialValue:DormStepMeterStatus.Asked(pick:preview?.meterPicked))
    }
    #else
    init(start: Step = .login, close: @escaping () -> Void) {
        self.close = close
        _step = State(initialValue:start)
        _account = State(initialValue:"")
        _password = State(initialValue:"")
        _savePassword = State(initialValue:false)
        _loginState = State(initialValue:.idle)
        _apartment = State(initialValue:nil)
        _meterAsked = State(initialValue:DormStepMeterStatus.Asked())
    }
    #endif

    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var water: ShowerModel
    /// 「先看看示例」: the root closes this guide over the sample.
    @Environment(SampleMode.self) private var sample
    /// Binds the dorm's hot-water controller when 「就是这间」 confirms the dorm.
    @StateObject private var dormFlow = DormSetupFlow()
    @State private var bindingWater = false
    /// Automatic binding already needed the dorm screen once; the next 「就是这间」 just continues
    /// (hot water can be finished later from 设置 › 热水).
    @State private var bindTried = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var step: Step
    @State private var login = false
    @State private var dormPicker = false
    @State private var issue: String?
    /// Why hot water was not bound, said under 「你住哪间」 until the next tap goes on.
    @State private var waterNote: String?
    /// Same-name apartment picked on the dorm step (candidate id); confirmed by 「就是这间」.
    @State private var apartment: String?
    /// The meter question last asked on the dorm step and the row picked (kept across the step).
    @State private var meterAsked: DormStepMeterStatus.Asked
    /// An apartment that halted before its rooms, tapped: the meter page opens where it halted.
    @State private var meterHalted: MeterWalkStop?
    @State private var meterPage = false
    @State private var account: String
    @State private var password: String
    /// 「保存密码，让小组件自动刷新」: on by default only while the account is the saved one.
    @State private var savePassword: Bool
    @State private var loginState: SchoolLoginState
    @FocusState private var loginFocus: SchoolLoginField?

    /// Keyboard up on the login step: mascot and body make room; the save-password note stays.
    private var keyboardUp: Bool { step == .login && loginFocus != nil }
    private var loginReady: Bool {
        !account.trimmingCharacters(in:.whitespaces).isEmpty && !password.isEmpty
    }

    // What the steps show: the DEBUG demo's values when previewing, the models' otherwise.
    // Release has no demo: `previewing` is false and every value is the model's.
    #if DEBUG
    private var previewing: Bool { preview != nil }
    /// The account saved on this phone (the demo's own when previewing).
    private var savedAccount: SchoolAccount? { previewing ? preview?.saved : campus.account }
    private var dorm: String? { previewing ? preview?.dorm : Theme.dorm(campus.room) }
    private var dormLocation: String? { previewing ? preview?.dormLocation : campus.profile?.directoryDormLocation }
    /// The demo's meter line under the dorm (nil: the lookup's).
    private var previewMeter: DormStepMeter? { preview.map { $0.meter ?? .hidden } }
    /// The demo's same-name apartments (nil: the lookup's).
    private var previewChoices: [LocationChoice]? { preview?.powerChoices }
    #else
    private var previewing: Bool { false }
    private var savedAccount: SchoolAccount? { campus.account }
    private var dorm: String? { Theme.dorm(campus.room) }
    private var dormLocation: String? { campus.profile?.directoryDormLocation }
    private var previewMeter: DormStepMeter? { nil }
    private var previewChoices: [LocationChoice]? { nil }
    #endif

    /// Footnote under the dorm: where it came from.
    static let dormSource = "学校账号里登记的"

    var body: some View {
        guide.onChange(of:step) { _, value in moved(value) }
    }

    private var guide: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                content
                    .id(step)
                    .transition(reduceMotion ? .opacity : .push(from:.trailing))
                    .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.topLeading)
            }
            .safeAreaInset(edge:.bottom, spacing:0) {
                // Accessibility sizes: the controls scroll with the content (end of the ScrollView)
                // instead of covering half the screen.
                if !typeSize.isAccessibilitySize { bottom.background(Theme.bg) }
            }
            .safeAreaInset(edge:.top, spacing:0) { skipBar }
            .toolbar(.hidden, for:.navigationBar)
            .navigationDestination(isPresented:$dormPicker) { CampusOnboardingView() }
            .navigationDestination(isPresented:$meterPage) { CampusPowerSetupView(start:meterHalted) }
        }
        .tint(Theme.accentText)
        .typesettingLanguage(Theme.typesetting)
        .accountSwitchAlert { openDormPicker() }
        .sheet(isPresented:$login) {
            CampusLoginSheet { value in
                do {
                    try await campus.adoptWebState(value)
                    issue = nil; loginState = .idle; password = ""
                    // The sheet shows 「正在读电量…」 until the card and meter are read.
                    await campus.refresh(force:true)
                    // Only from the login step: a repeated delivery must not skip the dorm step.
                    if step == .login { advance() }
                } catch {
                    issue = error as? SchoolLoginFailure == .busy ? SchoolLoginText.busy : "这次没登录上，再试一次。"
                }
            }
        }
        .onAppear {
            // The saved account is filled in, and its saved password stays saved on a new
            // sign-in unless the box is unticked.
            guard !previewing else { return }
            campus.reloadAccount()
            if account.isEmpty { account = campus.account?.account ?? "" }
            savePassword = SchoolAccount.savesPasswordByDefault(campus.account, typed:account)
        }
        .onChange(of:account) { old, new in
            // Another account typed in: somebody else's password is not kept unless they tick it.
            savePassword = SchoolAccount.savePassword(savePassword, afterEditFrom:old, to:new, saved:savedAccount)
        }
    }

    // MARK: Step content

    @ViewBuilder private var content: some View {
        ScrollView {
        VStack(alignment:.leading, spacing:0) {
            if !keyboardUp {
                // 52 pt at y≈104 on every step; the done screen's mascot is 76 pt at y≈180.
                let size: CGFloat = step == .done ? 76 : 52
                icon.frame(width:size, height:size, alignment:.leading)
                    .padding(.top,typeSize.isAccessibilitySize ? 32 : step == .done ? 76 : 0)
            }
            // Same title style on every step, done screen included (32 bold); 28 while the
            // login keyboard is up.
            Text(title).scaledFont(keyboardUp ? 28 : 32, .bold, relativeTo:.largeTitle).lineSpacing(2).foregroundStyle(Theme.ink)
                .fixedSize(horizontal:false, vertical:true)
                .padding(.top,keyboardUp ? 0 : 22)
                .accessibilityAddTraits(.isHeader)
            if !keyboardUp, let body = bodyText {
                Text(body).scaledFont(17).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true)
                    .padding(.top,10)
            }
            if step == .dorm, !choosingApartment, let dorm {
                Text(dorm).font(.system(size:40, weight:.semibold, design:appTheme.numberDesign)).foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .padding(.top,28)
                // The full location only when the electricity directory gave one: it is what
                // tells same-name dorms apart. The portal address alone has no apartment.
                if let dormLocation {
                    Text(dormLocation).scaledFont(17, .medium).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal:false, vertical:true)
                        .padding(.top,6)
                }
                Text(Self.dormSource).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                    .padding(.top,6)
                DormStepMeterStatus(asked:$meterAsked, preview:previewMeter, previewing:previewing) { halted in
                    meterHalted = halted; meterPage = true
                }
            }
            if step == .done { doneCard.padding(.top,28) }
            if step == .login {
                SchoolLoginForm(account:$account, password:$password, savePassword:$savePassword,
                                state:loginState, focus:$loginFocus, submit:submitLogin, webLogin:openWebLogin)
                    .padding(.top,keyboardUp ? 20 : 28)
            }
            if step == .dorm, !previewing, !campus.powerChoices.isEmpty {
                powerApartment.padding(.top,30)
            } else if step == .dorm, let choices = previewChoices, !choices.isEmpty {
                previewApartment(choices).padding(.top,30)
            }
            if let issue {
                Text(issue).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.redText)
                    .fixedSize(horizontal:false, vertical:true).padding(.top,16)
            }
            if let waterNote, Self.showsWaterNote(on:step) {
                Text(waterNote).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.notice)
                    .fixedSize(horizontal:false, vertical:true).padding(.top,16)
                    .accessibilityIdentifier("waterSkippedNote")
            }
        }
        .padding(.horizontal,24)
        .frame(maxWidth:.infinity, alignment:.leading)
        if typeSize.isAccessibilitySize { bottom.padding(.top,40) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .animation(reduceMotion ? .easeInOut(duration:0.2) : Theme.spring, value:keyboardUp)
    }

    @ViewBuilder private var icon: some View {
        switch step {
        case .login: Mascot(size:52)
        case .done: Mascot(size:76)
        case .dorm: symbol("house.fill")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName:name).font(.system(size:38, weight:.semibold)).foregroundStyle(Theme.accent)
            .accessibilityHidden(true)
    }

    private var title: String {
        switch step {
        case .login: return "登录学校账号"
        case .dorm where choosingApartment: return SameNameText.titleLead + SameNameText.titleAccent + SameNameText.titleTail
        case .dorm: return "你住哪间？"
        case .done: return "好了"
        }
    }

    private var bodyText: String? {
        switch step {
        case .login: return "用你在学校官网登录时的账号和密码。"
        case .dorm where choosingApartment: return SameNameText.hint(apartmentChoices)
        case .dorm: return dorm != nil ? "电量和热水都按这间宿舍来。" : "没读到你的宿舍，手动选一下。"
        case .done: return "以后在设置里都能改。"
        }
    }

    // MARK: Skip and done

    /// 「先不设置」, top right on 登录 and 宿舍 (17 ink2, 44 pt): closes the guide, marked seen.
    @ViewBuilder private var skipBar: some View {
        HStack {
            Spacer()
            if step != .done {
                Button(Self.skip, action:close)
                    .scaledFont(17).foregroundStyle(Theme.ink2)
                    .padding(.horizontal,12)
                    .frame(minWidth:44, minHeight:44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("onboardingSkip")
            }
        }
        .padding(.horizontal,12)
        .frame(minHeight:44)
    }

    /// 好了's card: 💧 and when the controller is checked.
    private var doneCard: some View {
        HStack(alignment:.firstTextBaseline, spacing:10) {
            Image(systemName:"drop.fill").scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(Self.doneNote).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal:false, vertical:true)
        }
        .padding(16)
        .frame(maxWidth:.infinity, alignment:.leading)
        .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
        .accessibilityElement(children:.combine)
        .accessibilityIdentifier("onboardingDoneNote")
    }

    /// Upstream 0.8.0-beta.2: the school directory can list two buildings with the same name.
    /// Automatic meter matching then needs the student to pick the right one once, by its
    /// full location (shared single-select list; 「就是这间」 confirms).
    @ViewBuilder private var powerApartment: some View {
        VStack(alignment:.leading, spacing:0) {
            if !campus.powerChoices.isEmpty {
                LocationChoiceList(choices:campus.powerChoices.map(\.choice), selection:$apartment)
                    .disabled(campus.matchingPower)
                    // A new list: an earlier pick may no longer be in it.
                    .onChange(of:campus.powerChoices) { _, _ in apartment = nil }
            }
            if let issue = campus.powerMatchIssue {
                Text(issue).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true).padding(.top,8)
                Button("再找一次电表") { campus.matchPowerAutomatically() }
                    .scaledFont(17, .medium).foregroundStyle(Theme.accentText)
                    .frame(minHeight:44).disabled(campus.matchingPower)
            }
        }
    }

    private var apartmentChoices: [LocationChoice] { previewChoices ?? campus.powerChoices.map(\.choice) }

    private var waitingForApartment: Bool { choosingApartment && apartment == nil }

    /// The dorm step lists same-name apartments; 「就是这间」 waits for a choice.
    private var choosingApartment: Bool {
        guard step == .dorm else { return false }
        if let choices = previewChoices { return !choices.isEmpty }
        return !campus.powerChoices.isEmpty
    }

    /// DEBUG demo: the same picker with sample locations; confirming does nothing.
    private func previewApartment(_ choices: [LocationChoice]) -> some View {
        LocationChoiceList(choices:choices, selection:$apartment)
    }

    // MARK: Bottom

    private var bottom: some View {
        VStack(spacing:0) {
            if step != .done && !keyboardUp {
                HStack(spacing:7) {
                    ForEach(0..<Self.dotted, id:\.self) { index in
                        Circle().fill(index == Self.dot(step) ? Theme.ink : Theme.ink3).frame(width:7, height:7)
                    }
                }
                .accessibilityElement().accessibilityLabel(Self.dotsLabel(step))
                .padding(.bottom,18)
            }
            Button(action:primary) {
                // Same pill style on every step (18 semibold, headline-relative).
                // Waiting for an apartment choice or logging in: the home dock's disabled look
                // (「正在结算…」: fill + ink2). Login fields not filled yet: fill + ink3.
                HStack(spacing:10) {
                    if loggingIn { ProgressView().tint(Theme.ink2) }
                    Text(primaryTitle)
                }
                    .scaledFont(18, .semibold, relativeTo:.headline).foregroundStyle(primaryInk)
                    .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                    .padding(.horizontal,20).padding(.vertical,8)
                    .frame(maxWidth:.infinity, minHeight:keyboardUp ? 52 : 60)
                    .background(primaryDimmed ? Theme.fill : Theme.pill, in:appTheme.buttonShape.shape)
                    .contentTransition(reduceMotion ? .opacity : .interpolate)
            }
            .buttonStyle(PressScaleStyle())
            .disabled(primaryDimmed || bindingWater || choosingApartment && campus.matchingPower)
            .accessibilityIdentifier("onboardingPrimary")
            .accessibilityLabel(primaryTitle)
            // Fixed slot below the pill so the pill doesn't jump between steps.
            ZStack(alignment:.top) {
                if step == .dorm && dorm != nil {
                    secondary(choosingApartment ? "都不是，换一间" : "换一间") { openDormPicker() }
                }
                if step == .login && !keyboardUp {
                    VStack(spacing:0) {
                        // For a look without an account (App Review): synthetic data, nothing stored or sent.
                        // Shut while the real shower is not over or its record not read (`LiveShowerGate`);
                        // `water` is observed, so the line follows its record.
                        if sample.gate.sampleAllowed {
                            secondary(SampleCopy.entry) { sample.enter() }
                                .disabled(loggingIn)
                                .accessibilityIdentifier("sampleEntry")
                        } else {
                            SampleEntryRefused(minHeight:46) { $0.scaledFont(17, .medium) }
                        }
                    }
                }
            }
            .frame(minHeight:keyboardUp ? 0 : 46, alignment:.top)
        }
        .padding(.horizontal,24)
        .padding(.bottom,keyboardUp ? 12 : 4)
        .animation(reduceMotion ? .easeInOut(duration:0.2) : Theme.spring, value:step)
    }

    /// The text button under the pill: 46 pt, 17 medium ink2.
    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action:action)
            .scaledFont(17, .medium).foregroundStyle(Theme.ink2)
            .frame(maxWidth:.infinity, minHeight:46)
    }

    private var primaryTitle: String {
        switch step {
        case .login:
            return SchoolLoginText.primary(loggingIn:loggingIn)
        case .dorm: return bindingWater ? "正在找宿舍的水控…" : dorm != nil ? "就是这间" : "选宿舍"
        case .done: return "开始用"
        }
    }

    private var loggingIn: Bool { step == .login && loginState == .loading }

    /// Login: dimmed until both fields are filled, and while logging in.
    private var primaryDimmed: Bool {
        if step == .login { return loggingIn || !loginReady }
        return waitingForApartment
    }

    private var primaryInk: ThemeColor {
        guard primaryDimmed else { return Theme.pillInk }
        return step == .login && !loggingIn || waitingForApartment ? Theme.ink3 : Theme.ink2
    }

    // MARK: Actions

    private func primary() {
        switch step {
        case .login:
            submitLogin()
        case .dorm:
            if choosingApartment {
                guard let apartment else { return }
                if previewing { bindWaterThenAdvance(); return }
                // Only on once the meter is saved: a pick that is gone from the list, or a save
                // that failed (said on this page), stays here.
                guard let candidate = campus.powerChoices.first(where:{ $0.id == apartment }) else { self.apartment = nil; return }
                Task { if await campus.choosePower(candidate) { bindWaterThenAdvance() } }
            } else if dorm != nil { bindWaterThenAdvance() } else { openDormPicker() }
        case .done: close()
        }
    }

    /// The dorm is confirmed: bind its hot-water controller too (one room, one controller), or open
    /// the dorm screen once when that needs a choice. Never blocks the guide.
    private func bindWaterThenAdvance() {
        guard !previewing, !bindTried, !water.configured else { advance(); return }
        guard !bindingWater else { return }
        bindingWater = true
        Task {
            let result = await dormFlow.autoBind(campus:campus, water:water)
            bindingWater = false
            switch Self.next(after:result) {
            case .advance: advance()
            case .stay(let note):
                // Said here; the next 「就是这间」 goes on.
                bindTried = true; waterNote = note
            case .choose: bindTried = true; openDormPicker()
            }
        }
    }

    /// After 「就是这间」's binding: on with the guide, here with why hot water was not bound (the
    /// next tap goes on), or the dorm screen for a real choice.
    enum BindNext: Equatable { case advance, stay(note: String), choose }

    static func next(after result: DormSetupFlow.AutoBind) -> BindNext {
        switch result {
        case .bound, .unavailable: return .advance
        case .failed(let why): return .stay(note:why.warmText)
        case .needsChoice: return .choose
        }
    }

    /// The hot-water note is said under 「你住哪间」 only.
    static func showsWaterNote(on step: Step) -> Bool { step == .dorm }

    /// One login with the form's account and password; never retried (failures count towards
    /// the school's lock). Wrong → password cleared and focused; anything the school put in the
    /// way → said by cause under the fields, and 登录 can be tried again.
    private func submitLogin() {
        guard step == .login, loginReady, loginState.allowsDirectLogin else { return }
        if previewing { advance(); return }
        loginFocus = nil
        loginState = .loading
        let name = account, secret = password, save = savePassword
        Task {
            let next = await campus.submitLogin(account:name, password:secret, savePassword:save)
            if next.clearsTypedPassword { password = "" }
            loginState = next
            if next == .wrong { loginFocus = .password }
            if next == .idle, step == .login { advance() }
        }
    }

    /// The school's own page (behind the loading cover); nothing to save on that path.
    private func openWebLogin() {
        if previewing { advance(); return }
        loginFocus = nil
        login = true
    }

    private func openDormPicker() {
        guard !previewing else { return }
        dormPicker = true
    }

    private func advance() {
        guard let next = Step(rawValue:step.rawValue + 1) else { close(); return }
        issue = nil
        withAnimation(reduceMotion ? .easeInOut(duration:0.2) : Theme.spring) { step = next }
    }
}
