import Foundation
import Core

/// One same-name meter offered when the electricity match is ambiguous, told apart by its
/// full location (校区 · 公寓 · 楼栋 · 房间): the names alone are identical.
struct PowerChoice: Identifiable, Equatable {
    var id: String { candidate.id }
    let candidate: MeterCandidate
    /// Who was signed in when the match that offered it started: a pick after someone else
    /// signed in is refused.
    let stamp: Int
    var meter: Meter { candidate.meter }
    var location: String { candidate.location }
    /// Row for the shared same-name list: short 「3 栋 108」 over the full location.
    var choice: LocationChoice { LocationChoice(id:id, title:Theme.dorm(meter.name) ?? meter.name, location:location) }
}

/// UI state over `SchoolSession` (refresh, electricity resolution, sign-in/out). No school logic here.
/// Runs on the `CampusServices` it is given: the live app's (`shared`), or a sample's.
@MainActor final class CampusModel: ObservableObject {
    static let shared = CampusModel(services:AppEnvironment.live, stack:AppEnvironment.liveSchoolStack, reminders:.shared,
                                    hotWater:{ ShowerModel.shared })
    @Published private(set) var configured = false
    @Published private(set) var loading = false
    @Published private(set) var snapshot: HomeSnapshot = .empty
    @Published private(set) var profile: SchoolProfile?
    @Published private(set) var issue: String?
    /// Several refreshes in a row ended without storing their numbers (the Keychain refusing
    /// writes): the home update line says so.
    @Published private(set) var notSaving = false
    /// The automatic meter lookup: when it starts, and the list or stopped level it left.
    @Published private(set) var lookup = MeterLookupGate()
    /// A same-name choice is being saved.
    @Published private(set) var savingChoice = false
    @Published private(set) var powerMatchIssue: String?
    /// The account signed in with the app's own form (kept by a web sign-in only when the card
    /// shows the same person). Its password is present only when the user chose to save it.
    @Published private(set) var account: SchoolAccount?
    /// A login was a different person; the alert is shown once by the top-most screen.
    @Published var switchNotice: AccountSwitchNotice?
    /// 「去设置热水」 from a screen outside Settings: Settings opens 热水 when it appears.
    @Published var hotWaterSetupRequested = false
    /// The widget's 「打开 App 更新」 during a paused automatic login: Settings opens 学校账号.
    @Published var accountPageRequested = false
    /// Sign-out left something behind (a Keychain item or the widget snapshot could not be
    /// deleted): Settings › 学校账号 says so, and shows what is still stored.
    @Published var signOutFailed = false
    /// Bumped by a sign-out and by a sign-in of someone else (or someone not known to be the
    /// same): pages showing the previous person's school data close.
    @Published private(set) var personChanges = 0
    private var lastRefresh: Date?
    /// The last refresh read the card (its session alive, or renewed).
    private var lastReadCard = false
    private var refreshesRunning = 0
    /// Refreshes the Keychain interrupted one after another (writes refused).
    private var interruptions = InterruptionStreak()
    /// Bumped by `signOut()`: a refresh that returns afterwards must not put the old values back.
    private var signOutGeneration = 0
    let services: CampusServices
    private let session: SchoolSession
    /// The school session these models read (校园卡记录's pages).
    var schoolSession: SchoolSession { session }
    private let refresher: SnapshotRefresher
    private let reminders: Reminders
    /// The hot-water model on the same services (its binding goes with an account switch).
    private let hotWater: () -> ShowerModel?
    /// Sign-outs in order; sign-ins wait for them (`finished()`).
    private let signOuts: SchoolSignOut
    private var schoolVault: StoredSchoolVault { services.schoolVault }

    init(services: CampusServices, stack: SchoolRefreshStack, reminders: Reminders, hotWater: @escaping () -> ShowerModel?) {
        self.services = services
        session = stack.session
        refresher = stack.refresher
        self.reminders = reminders
        self.hotWater = hotWater
        signOuts = SchoolSignOut(session:stack.session, refresher:stack.refresher)
        reload()
    }

    /// Launch, before the launch lookup: a meter an older build bound to the campus node counts
    /// as none, so the lookup walks to the room's own (`SchoolSession.dropCampusWideMeter`).
    func dropCampusWideMeter() async {
        if (try? await session.dropCampusWideMeter()) == true { reload() }
    }

    /// Re-read the Keychain (launch, back in the foreground, after sign-in/out). A read that
    /// fails (before the first unlock after a reboot, when the app is pre-warmed) changes nothing.
    func reload() {
        let shown = SchoolShownItems(signedIn:configured, profile:profile, account:account).reread(from:schoolVault)
        configured = shown.signedIn
        profile = shown.profile
        account = shown.account
        snapshot = refresher.latest()
    }

    /// Only the saved account: a refresh in this or the widget's process may have paused or
    /// held the password since the last `reload()`.
    func reloadAccount() {
        let stored = SchoolShownItems(signedIn:configured, profile:profile, account:account).reread(from:schoolVault).account
        if stored != account { account = stored }
    }

    /// Settings › 学校账号 › 保存密码.
    var passwordSaved: Bool { SchoolAccount.savesPasswordByDefault(account) }

    var address: DormAddress? { profile?.residence?.address }
    /// 「99 栋 991」 style label, or 「未配置」.
    var room: String {
        if let address { return address.building + " 栋 " + address.room }
        return Theme.dorm(snapshot.roomLabel ?? profile?.meter?.label ?? "") ?? "未配置"
    }
    var powerConfigured: Bool { profile?.meter != nil }
    /// The lookup stopped at a level to choose from.
    static let stoppedIssue = MeterPageText.stoppedIssue
    /// The lookup is running, or a same-name choice is being saved.
    var matchingPower: Bool { lookup.running || savingChoice }
    var powerChoices: [PowerChoice] { lookup.choices.map { PowerChoice(candidate:$0, stamp:lookup.choicesStamp ?? -1) } }
    /// Where the automatic lookup stopped (a level that did not match the dorm exactly once):
    /// the meter page opens there.
    var powerStop: MeterWalkStop? { lookup.pageStop(meterBound:powerConfigured) }
    /// The lookup stopped with rooms in several apartments: which one (nil once a meter is bound).
    var powerQuestion: MeterQuestion? { powerStop.flatMap { MeterQuestion($0, address:address ?? demoDorm) } }
    #if DEBUG
    /// The dorm of a DEBUG demo stop (nil otherwise): the question names its building and room.
    private var demoDorm: DormAddress?
    #else
    private var demoDorm: DormAddress? { nil }
    #endif
    /// Several apartments to tell apart and one not read: the meter page shows no list.
    var powerUnfinished: MeterWalkStop? { powerConfigured ? nil : lookup.unfinished }
    /// The stamp a pick of `powerQuestion`'s rows is saved under.
    var powerQuestionStamp: Int { lookup.stopStamp ?? -1 }
    /// What onboarding's 「你住哪间」 step says about the meter.
    var dormStepMeter: DormStepMeter {
        DormStepMeter(running:lookup.running, bound:powerConfigured, stop:lookup.stop, issue:powerMatchIssue, address:address)
    }
    var balance: Decimal? { snapshot.card.value?.yuan }
    var meter: Meter? { snapshot.power.value }

    // MARK: Refresh

    /// Foreground refresh; `force` skips the 60 s throttle. While a refresh is running, a second
    /// call (pull-to-refresh, foreground, background task) waits for it and shows its result.
    /// A forced call never takes the result of a read that started before a sign-in or meter
    /// change (`SnapshotRefresher.noteChange`): it waits for that read and reads again.
    func refresh(force: Bool = false, inBackground: Bool = false) async {
        guard configured else { return }
        if !force, refreshesRunning == 0, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        refreshesRunning += 1; loading = true
        defer { refreshesRunning -= 1; loading = refreshesRunning > 0 }
        let started = signOutGeneration
        let report = await refresher.refresh(inBackground:inBackground, includingChanges:force)
        lastReadCard = report.outcome == .ok
        guard started == signOutGeneration else { return }
        snapshot = report.snapshot
        reloadAccount()
        // A cancelled refresh (the view went away, the pull was abandoned) reads as offline; that
        // says nothing about the school, so it neither shows an issue nor counts as a refresh.
        guard !Task.isCancelled else { return }
        // The widget held the lease all along (reading, or suspended while holding it): its
        // numbers, if any, are in the snapshot above. Nothing failed here, so no issue; the next
        // pull tries again.
        guard !report.leaseBusy else { return }
        // The saved password changed while this read ran (or the Keychain refused a write):
        // nothing to report, the numbers stay, and the next refresh is not held off. The same when
        // this read lost the lease (back from a long suspension, say): nothing failed. Several
        // interruptions in a row are the Keychain refusing writes: that is shown.
        notSaving = interruptions.record(report.outcome)
        guard report.outcome != .interrupted, report.outcome != .leaseLost else {
            issue = nil
            return
        }
        lastRefresh = Date()
        switch report.outcome {
        case .ok: issue = nil
        case .needsLogin: issue = "学校登录过期了，重新登录一下。"
        case .failed(let e): issue = e.userMessage
        case .notSignedIn: configured = false; issue = nil
        case .interrupted, .leaseLost: issue = nil
        }
        profile = SchoolShownItems(signedIn:configured, profile:profile, account:account).reread(from:schoolVault).profile
        reminders.evaluateCampus(snapshot)
        if report.outcome == .ok {
            reminders.campusRead(snapshot)
        }
    }

    /// 校园卡记录, recharge or the hot-water hand-off found the card session expired: renewed the
    /// way home renews it (a forced refresh, under the lease). True when that read the card again.
    func renewCardSession() async -> Bool {
        guard configured else { return false }
        await refresh(force:true)
        return lastReadCard
    }

    // MARK: Sign-in

    /// The official ecykt page finished signing in: adopt its `elecampus_state`, and keep the
    /// dorm address the portal page showed (read by the same sign-in).
    func adoptWebState(_ login: CampusWebLogin) async throws {
        // A sign-out asked for just before must not delete what this stores.
        await signOuts.finished()
        let started = signOutGeneration
        let session = session, state = login.state
        // Under the lease like the password sign-in: never beside the widget's own login.
        // A sign-in that throws after its writes began has changed the person too.
        var counted = false
        let summary = try await SchoolSession.watchingPerson(on:session, {
            try await refresher.holdingLease { owning in
                try await session.adoptWebState(state, owning:owning)
            }
        }, changed:{ personChanges += 1; counted = true })
        if summary.switchedAccount || summary.previousPersonUnconfirmed {
            if !counted { personChanges += 1 }
            await previousPersonCleared(unconfirmed:!summary.switchedAccount, dormAndMeterCleared:summary.dormAndMeterCleared)
        }
        await refresher.noteChange()
        // Signed out (or reset) while that ran: the dorm must not be written back.
        guard started == signOutGeneration else { return }
        let raw = login.dormAddress.trimmingCharacters(in:.whitespacesAndNewlines)
        if !raw.isEmpty {
            var stored = (try? schoolVault.profile()) ?? nil ?? SchoolProfile()
            if stored.residence?.raw != raw {
                stored.residence = PortalResidence(raw:raw)
                stored.meter = nil
            }
            try schoolVault.saveProfile(stored)
        }
        reload(); issue = nil; lastRefresh = nil
        lookup.clear(); powerMatchIssue = nil
        // Every sign-in, from any screen: the meter is looked for when none is bound.
        matchPowerAutomatically(.signedIn)
    }

    /// 登录 on the login form (first run and 重新登录学校账号): one login, never retried (failures
    /// count towards the school's lock), then a forced refresh. Returns the form's next state:
    /// `.idle` once signed in, `.wrong` (clear and focus the password), `.cannotDirect` (offer the
    /// school's web page) or `.failed` with the text to show.
    func submitLogin(account: String, password: String, savePassword: Bool) async -> SchoolLoginState {
        do {
            try await signIn(account:account.trimmingCharacters(in:.whitespaces), password:password, savePassword:savePassword)
            await refresh(force:true)
            return .idle
        } catch SchoolLoginFailure.wrongCredentials {
            return .wrong
        } catch SchoolLoginFailure.cannotLoginDirectly {
            return .cannotDirect
        } catch {
            return .failed(SchoolLoginText.text(error))
        }
    }

    /// The app's own login form. Throws `SchoolLoginFailure` for the login itself (shown on the
    /// form), or a service / storage error for the steps after it.
    func signIn(account: String, password: String, savePassword: Bool) async throws {
        // A sign-out asked for just before must not delete what this stores.
        await signOuts.finished()
        let session = session
        // A sign-in that throws after its writes began has changed the person too.
        var counted = false
        let summary = try await SchoolSession.watchingPerson(on:session, {
            try await refresher.holdingLease { owning in
                try await session.signIn(account:account, password:password, savePassword:savePassword, owning:owning)
            }
        }, changed:{ personChanges += 1; counted = true })
        if summary.switchedAccount || summary.previousPersonUnconfirmed {
            if !counted { personChanges += 1 }
            await previousPersonCleared(unconfirmed:!summary.switchedAccount, dormAndMeterCleared:summary.dormAndMeterCleared)
        }
        await refresher.noteChange()
        reload(); issue = nil; lastRefresh = nil
        lookup.clear(); powerMatchIssue = nil
        // Every sign-in, from any screen: the meter is looked for when none is bound.
        matchPowerAutomatically(.signedIn)
    }

    /// The login was someone else, or nothing showed it was the same person: Core already
    /// dropped their school data. Here: the widget
    /// snapshot, the hot-water binding made with their identity, and the one-time alert.
    /// Laundry (U净) is its own login and stays.
    private func previousPersonCleared(unconfirmed: Bool, dormAndMeterCleared: Bool) async {
        let refresher = refresher
        let hotWater = await AccountSwitch.clearPreviousPerson(
            snapshot:{ try await refresher.clear() },
            hotWater:{ [hotWater] in hotWater()?.clearBindingForAccountSwitch() ?? AccountSwitch.HotWater.none })
        snapshot = .empty
        switchNotice = AccountSwitchNotice(previousPersonUnconfirmed:unconfirmed, dormAndMeterCleared:dormAndMeterCleared,
                                           hotWaterCleared:hotWater.noticed)
    }

    /// Settings › 学校账号 › 保存密码 on / 重新输入密码: one login checks the password before it
    /// is kept. Never switches person: Core refuses another account (`differentAccount`).
    /// Without a known account (signed in on the web page) the typed one is checked against
    /// the signed-in card.
    func savePassword(_ password: String, account typed: String?) async throws {
        // A sign-out asked for just before must not delete what this stores.
        await signOuts.finished()
        let known = account?.account
        guard let name = known ?? typed, !name.isEmpty else { throw SchoolLoginFailure.wrongCredentials }
        let session = session
        try await refresher.holdingLease { owning in try await session.savePassword(password, account:name, owning:owning) }
        reload()
        if known == nil { await refresh(force:true) }
    }

    /// 保存密码 off: the password goes; the account stays for display. Written inside the lease
    /// file's lock, so a widget refresh that read the account before can't write the password
    /// back. A failed write, or a lease file that can't be locked, is thrown with the password
    /// still stored: the switch reads it back (on) and says it wasn't turned off.
    func forgetPassword() async throws {
        defer { reload() }
        try await session.forgetPassword(lockingWith:refresher.lease)
    }

    /// Reset, before the stores are cleared: a refresh still running must not write the old
    /// values back afterwards, and the widget snapshot is cleared first so nothing rewrites it.
    func signOutForReset() async {
        signOutGeneration += 1; personChanges += 1
        _ = await signOuts.start().value
        configured = false; snapshot = .empty; profile = nil; issue = nil; account = nil
        lookup.clear(); powerMatchIssue = nil; lastRefresh = nil
    }

    func signOut() {
        signOutGeneration += 1; personChanges += 1
        // The lease goes first: a widget read in the middle of a login loses it and writes
        // nothing. Waiting for its file lock happens off the main thread.
        let signedOut = signOuts.start()
        Task {
            guard !(await signedOut.value) else { return }
            // Show what is still stored, so 退出登录 can be tried again.
            reload()
            signOutFailed = true
        }
        configured = false; snapshot = .empty; profile = nil; issue = nil; account = nil
        lookup.clear(); powerMatchIssue = nil
    }

    // MARK: Electricity

    /// Look for the dorm's meter (`MeterLookupGate`): at launch, after every sign-in, or
    /// 「再找一次电表」 (`manual`, the default). Never by itself in the foreground or after a refresh.
    func matchPowerAutomatically(_ trigger: MeterLookupGate.Trigger = .manual) {
        guard lookup.start(trigger, signedIn:configured, meterBound:powerConfigured) else { return }
        powerMatchIssue = nil
        Task {
            let before = await session.personStamp()
            var again = false
            var found: ElectricityResolution?
            do {
                // Core runs it again for the next person if someone else signed in meanwhile.
                let (stamp, answer) = try await session.matchElectricity()
                // Someone else signed in after it answered: none of it is theirs, their own runs.
                if await session.isSamePerson(since:stamp) {
                    // Read again as it lands: a meter picked by hand meanwhile wins over the answer.
                    let bound = ((try? schoolVault.profile()) ?? nil)?.meter != nil
                    found = answer
                    if lookup.answered(answer, stamp:stamp, meterBound:bound) {
                        switch answer {
                        case .matched, .alreadyBound, .chooseAmong: break
                        case .stopped: powerMatchIssue = Self.stoppedIssue
                        case .unfinished(let at): powerMatchIssue = MeterPageText.unfinished(at.level)
                        case .noAddress: powerMatchIssue = "学校没给出宿舍地址，去「电表」里选一下。"
                        }
                    }
                } else {
                    again = true
                }
            } catch {
                // Signed out or someone else signed in meanwhile: this lookup was theirs, say
                // nothing; whoever is signed in now gets their own (signed out: `configured` is
                // false and nothing runs). What was shown before stays.
                if await session.isSamePerson(since:before) { powerMatchIssue = AppErrorText.text(error) } else { again = true }
            }
            // Ended before the refresh below: a lookup asked for meanwhile may start from here on.
            let signedInMeanwhile = lookup.ended()
            var bound = false
            if case .matched? = found { bound = true } else if case .alreadyBound? = found { bound = true }
            if bound { profile = (try? schoolVault.profile()) ?? nil }
            if again || signedInMeanwhile { matchPowerAutomatically(.signedIn) }
            if bound {
                await refresher.noteChange()
                await refresh(force:true)
            }
        }
    }

    /// Binds one same-name choice. True once it is saved; false (the reason in
    /// `powerMatchIssue`, the choices kept) when it could not be.
    @discardableResult func choosePower(_ choice: PowerChoice) async -> Bool {
        guard !matchingPower else { return false }
        savingChoice = true
        defer { savingChoice = false }
        do {
            try await session.chooseMatchedMeter(choice.candidate, since:choice.stamp)
        } catch {
            powerMatchIssue = AppErrorText.text(error)
            return false
        }
        await refresher.noteChange()
        lookup.clear(); powerMatchIssue = nil
        profile = (try? schoolVault.profile()) ?? nil
        Task { await refresh(force:true) }
        return true
    }

    /// Manual picker.
    func directory(parent: String?) async throws -> [PowerNode] { try await session.directory(parent:parent) }
    func meterRows(nodeID: String) async throws -> [Meter] { try await session.meterRows(nodeID:nodeID) }
    /// `stamp`: `personStamp()` when the picker opened.
    func chooseMeter(nodeID: String, meter: Meter, path: [String] = [], since stamp: Int) async throws {
        try await session.chooseMeter(nodeID:nodeID, meter:meter, path:path, since:stamp)
        await refresher.noteChange()
        profile = (try? schoolVault.profile()) ?? nil
        lookup.clear(); powerMatchIssue = nil
        await refresh(force:true)
    }

    // MARK: Recharge / hot water hand-off

    /// Both write the live card session back: under the lease, so never beside the widget's refresh.
    /// An expired card session is renewed once as home renews it, then the step is tried again.
    func rechargeSession(_ kind: RechargeKind) async throws -> RechargeWebSession {
        let session = session, refresher = refresher
        return try await CardSessionRenewal.renewingOnce({
            try await refresher.holdingLease { owning in try await session.rechargeSession(kind, owning:owning) }
        }, renew: { await renewCardSession() })
    }
    func showerHandoff() async throws -> ShowerHandoff {
        let session = session, refresher = refresher
        return try await CardSessionRenewal.renewingOnce({
            try await refresher.holdingLease { owning in try await session.showerHandoff(owning:owning) }
        }, renew: { await renewCardSession() })
    }
    /// Taken before `showerHandoff()`; `isSamePerson(since:)` says whether its identity still
    /// belongs to whoever is signed in.
    func personStamp() async -> Int { await session.personStamp() }
    func isSamePerson(since stamp: Int) async -> Bool { await session.isSamePerson(since:stamp) }

    #if DEBUG
    /// Demo dorm, 99 栋 991 (synthetic).
    nonisolated static let demoAddress = DormAddress.parse("星湖校区99栋9号1层991房")
    /// Demo: the lookup stopped at the apartments, 半山公寓 and 兰香公寓 both with a 99栋 991.
    nonisolated static var demoApartmentStop: MeterWalkStop {
        let campus = PowerNode(id:"991001", name:"星湖校区")
        let apartments = [PowerNode(id:"991001001", name:"半山公寓"), PowerNode(id:"991001007", name:"兰香公寓")]
        let candidates = apartments.enumerated().map { index, apartment in
            MeterCandidate(meter:Meter(comAddress:"99000000\(index)991", name:"99栋991"),
                           path:[campus, apartment, PowerNode(id:apartment.id + "000109", name:"99栋"),
                                 PowerNode(id:apartment.id + "000109001", name:"1楼"), PowerNode(id:apartment.id + "109001003", name:"991")])
        }
        return MeterWalkStop(level:.apartment, path:[campus],
                             options:apartments + [PowerNode(id:"991001002", name:"樱花公寓")],
                             suggested:apartments.map(\.id), candidates:candidates)
    }

    /// Demo: as `demoApartmentStop`, but 半山公寓's 99栋 names its floors 「A区」「B区」 (halted at
    /// 选楼层): its row opens the picker there; 兰香公寓's room binds.
    nonisolated static var demoMixedStop: MeterWalkStop {
        var stop = demoApartmentStop
        let banshan = stop.options[0]
        stop.candidates = Array(stop.candidates.dropFirst())
        stop.halted = [MeterWalkStop(level:.floor, path:[stop.path[0], banshan, PowerNode(id:banshan.id + "000109", name:"99栋")],
                                     options:[PowerNode(id:banshan.id + "000109091", name:"A区"),
                                              PowerNode(id:banshan.id + "000109092", name:"B区")])]
        return stop
    }

    /// Demo: the lookup stopped at the dorm's buildings (two named 99栋); `running` looks again,
    /// `slow` failed on a slow school. Synthetic, nothing is read.
    func demoMeterStop(running: Bool = false, slow: Bool = false, ask: Bool = false, unfinished: Bool = false, mixed: Bool = false) {
        let stop = mixed ? Self.demoMixedStop : ask || unfinished ? Self.demoApartmentStop : MeterWalkStop(level:.building,
                                 path:[PowerNode(id:"991001", name:"星湖校区"), PowerNode(id:"991001001", name:"半山公寓")],
                                 options:[PowerNode(id:"991001001000108", name:"98栋"), PowerNode(id:"991001001000109", name:"99栋"),
                                          PowerNode(id:"991001001000110", name:"99 栋"), PowerNode(id:"991001001000111", name:"100栋")],
                                 suggested:["991001001000109", "991001001000110"])
        var gate = MeterLookupGate()
        _ = gate.start(.manual, signedIn:true, meterBound:false)
        var unread = stop
        unread.candidates = []
        gate.answered(unfinished ? .unfinished(unread) : .stopped(stop), stamp:0)
        _ = gate.ended()
        if running { _ = gate.start(.manual, signedIn:true, meterBound:false) }
        lookup = gate
        demoDorm = ask || mixed ? Self.demoAddress : nil
        powerMatchIssue = unfinished ? MeterPageText.unfinished(.apartment)
            : slow ? ServiceError.timedOut.userMessage : running ? nil : Self.stoppedIssue
    }
    #endif
}
