import SwiftUI
import Core

struct CampusLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = CampusBrowserState()
    @State private var manual = false
    /// The automatic read and the manual 读取 button can both produce a login: deliver it once.
    @State private var delivered = false
    /// Adopts the login and reads the card and meter; the sheet shows 「正在读电量…」 meanwhile and
    /// closes when it returns (or after `readLimit`, leaving the read running).
    let receive: (CampusWebLogin) async -> Void
    /// DEBUG demo: keep the opening state (no page is loaded).
    var holdOpening = false
    private static let readLimit: Duration = .seconds(20)
    private func deliver(_ config: CampusWebLogin) {
        guard !delivered else { return }
        delivered = true
        browser.progress.delivered()
        // Not cancelled by the time limit: a slow read finishes after the sheet has closed.
        Task { await receive(config); close() }
        Task { try? await Task.sleep(for:Self.readLimit); close() }
    }
    @State private var closed = false
    private func close() {
        guard !closed else { return }
        closed = true; dismiss()
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                if !hidden {
                    Text(browser.status)
                        .font(.footnote).foregroundStyle(.secondary).padding(12)
                }
                ZStack {
                    OfficialCampusBrowser(state:browser, loads:!holdOpening)
                    if hidden {
                        VStack(spacing:16) {
                            ProgressView()
                            VStack(spacing:6) {
                                Text(browser.progress.text ?? CampusLoginProgress.openingText)
                                    .font(.subheadline).foregroundStyle(Theme.ink)
                                    .accessibilityIdentifier("campusLoginStage")
                                // Space kept from the start so the spinner doesn't move when it appears.
                                let slow = browser.progress.slowNote(now:browser.now)
                                Text(slow ?? CampusLoginProgress.slowText).font(.footnote).foregroundStyle(.secondary)
                                    .opacity(slow == nil ? 0 : 1)
                                    .accessibilityHidden(slow == nil)
                            }
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration:0.2), value:browser.progress.slowNote(now:browser.now))
                        }
                        .padding(.horizontal,32).padding(.bottom,60)
                        .frame(maxWidth:.infinity,maxHeight:.infinity).background(Theme.bg)
                        .accessibilityElement(children:.combine)
                    }
                }
                if let issue = browser.issue { Text(issue).font(.footnote).foregroundStyle(.orange).padding(10) }
                if browser.stalled { Button("再连一次") { browser.retry?() }
                    .buttonStyle(.borderedProminent).padding().disabled(browser.reading) }
                if browser.stalled || manual {Button("备用方式") { manual.toggle() }.font(.footnote).padding(.vertical,4)}
                if manual { Button {
                    Task { do { let config = try await browser.read(); deliver(config) }
                        catch { browser.issue = "登录信息没读到，再试一次。" } }
                } label: { Text(browser.reading ? "正在读取…" : "从当前页面读取").frame(maxWidth:.infinity,minHeight:44) }
                    .buttonStyle(.borderedProminent).padding().disabled(browser.reading || delivered).accessibilityIdentifier("readCampusLogin")
                }
            }.background(Theme.bg).navigationTitle("登录学校账号").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
                .onReceive(browser.$connected.compactMap { $0 }) { config in deliver(config) }
                .task {
                    // One clock for the 8 s slow line and the opening fallback.
                    while !Task.isCancelled {
                        try? await Task.sleep(for:.seconds(1))
                        browser.now = Date()
                        if !holdOpening { browser.progress.tick(now:browser.now) }
                    }
                }
        }
        // An account-switch alert waits until this sheet has closed.
        .holdsAccountSwitchAlert()
    }
    /// Spinner instead of the page (a stalled automation shows the page and its buttons).
    private var hidden: Bool { browser.progress.concealed && !browser.stalled }
}

struct CampusOnboardingView: View {
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var water: ShowerModel
    @State private var login = false
    /// 重新登录 once signed in: the account-and-password sheet (the web page is its fallback), so
    /// a saved password is checked and kept instead of silently dropped by a web sign-in.
    @State private var relogin = false
    @State private var offeredLogin = false
    @State private var importingPlatform = false
    /// Dorm → hot-water controller binding; shared with the first-run guide's dorm step.
    @StateObject private var flow = DormSetupFlow()
    private let levels = ["校区","楼栋","楼层","宿舍"]
    var body: some View {
        Form {
            if water.profile == nil && flow.identity == nil {
                Section("热水") {
                    Text("登录学校账号后会自动读到宿舍和水控，不用导入文件。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if campus.configured {Button("再连一次") {Task {await flow.prepare(campus:campus,water:water)}}.disabled(flow.busy || !water.mayImport || campus.loading)}
                    DisclosureGroup("导入热水配置") {
                        Button("选择配置文件") {importingPlatform = true}
                            .disabled(flow.busy || !water.mayImport).accessibilityIdentifier("importWaterPlatform")
                        Text("平时用不到，只在从旧版迁移或排查问题时用。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let address = campus.profile?.residence?.raw, !address.isEmpty {
                Section("学校登记宿舍") {
                    Text(address).font(.subheadline)
                    if flow.autoMatched {Text(campus.powerConfigured ? "宿舍和电表都找到了。" : "找到你的宿舍了，核对一下再保存。")
                        .font(.footnote).foregroundStyle(.secondary)}
                }
            }
            AutomaticPowerSection()
            Section {
                Button { if campus.configured { relogin = true } else { login = true } } label: {
                    Label(campus.configured ? "重新登录" : "登录并连接校园卡",systemImage:"person.crop.circle")
                }
                    .accessibilityIdentifier("officialCampusLogin").disabled(flow.busy)
                if campus.configured {
                    Label("已读取学校账号",systemImage:"checkmark.circle").foregroundStyle(.green)
                    Button(flow.identity == nil ? "继续读取宿舍" : "重新读取宿舍") { Task { await flow.prepare(campus:campus,water:water) } }
                        .disabled(flow.busy || !water.mayImport || campus.loading).accessibilityIdentifier("prepareDormOnboarding")
                }
            } header: { Text("学校账号") } footer: { Text("密码只交给学校，不经过我们。登录后会读到你的校园卡和宿舍。") }
            if flow.identity != nil {
                Section("热水宿舍") {
                    if flow.autoMatched, let address = campus.address {
                        LabeledContent("已匹配宿舍",value:Theme.dorm(address.roomLabel) ?? address.roomLabel)
                        DisclosureGroup("更换宿舍") {dormMenus}
                    } else {dormMenus}
                    ForEach(flow.machines, id:\.machineId) { machine in
                        VStack(alignment:.leading,spacing:10) {
                            Label(machine.name,systemImage:"drop").font(.headline)
                            Text("水控编号 " + machine.machineId).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text("核对是你的宿舍后保存。保存不会出水，也不会更改学校绑定。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("就是这间") {Task {await flow.save(machine,water:water)}}
                                .buttonStyle(.borderedProminent).frame(minHeight:44)
                                .disabled(flow.busy || !water.mayImport || campus.loading || flow.saved).accessibilityIdentifier("saveDormBinding")
                        }.padding(.vertical,6)
                    }
                }
            }
            if flow.busy { Section { HStack { ProgressView(); Text("正在读取学校信息…") } } }
            if let issue = flow.issue { Section { Text(issue).foregroundStyle(.orange).font(.footnote) } }
            if flow.saved {
                Section {
                    Label("宿舍已保存",systemImage:"checkmark.circle.fill").foregroundStyle(.green)
                    NavigationLink("前往连接检查") { AdvancedSettingsView() }
                    Text("靠近宿舍水控，在“连接检查”里核对水控。也可以直接开始洗澡，校日常会先核对水控编号。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("学校账号与宿舍").navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented:$importingPlatform,allowedContentTypes:[.json,.data]) {result in
                do {
                    try water.importConfig(result.get()); flow.issue = nil
                    if campus.configured {Task {try? await Task.sleep(for:.milliseconds(300)); await flow.prepare(campus:campus,water:water)}}
                    else {login = true}
                } catch {flow.issue = "没导入成功。选热水平台给的配置文件，别用别人的完整配置。"}
            }
            .sheet(isPresented:$login) { CampusLoginSheet { value in
                do {
                    try await campus.adoptWebState(value)
                    flow.reset()
                    await campus.refresh(force:true)
                    Task { await flow.prepare(campus:campus,water:water) }
                } catch {
                    // The widget is refreshing (and may be signing in): nothing was stored.
                    flow.issue = error as? SchoolLoginFailure == .busy ? SchoolLoginText.busy : "这次没登录上，再试一次。"
                }
            } }
            .sheet(isPresented:$relogin) {
                SchoolReloginSheet(signedIn:{
                    flow.reset()
                    Task { await flow.prepare(campus:campus,water:water) }
                })
            }
            .task {
                if campus.configured {
                    if !water.configured && flow.identity == nil { await flow.prepare(campus:campus,water:water) }
                } else if !offeredLogin {
                    offeredLogin = true
                    login = true
                }
            }
            .scrollContentBackground(.hidden).background(NothingTheme.background).tint(NativeTheme.tint)
    }
    private var dormMenus: some View {
        ForEach(0..<4,id:\.self) {level in
            if !flow.options[level].isEmpty {
                Menu {
                    ForEach(flow.options[level], id:\.id) {option in
                        Button(option.name) {Task {await flow.choose(option,at:level)}}
                    }
                } label: {LabeledContent(levels[level],value:flow.selected.count > level ? flow.selected[level].name : "选一下")}
                    .disabled(flow.busy).accessibilityIdentifier("dormLevel\(level)")
            }
        }
    }
}

/// Dorm → hot-water controller binding over `ShowerOnboarding` (direct platform). Used by the
/// dorm screen and by the first-run guide. Saving never starts water or changes school data.
@MainActor final class DormSetupFlow: ObservableObject {
    @Published private(set) var identity: ShowerUser?
    @Published private(set) var options: [[AreaNode]] = [[],[],[],[]]
    @Published private(set) var selected: [AreaNode] = []
    @Published private(set) var machines: [ShowerMachine] = []
    @Published private(set) var autoMatched = false
    @Published private(set) var busy = false
    @Published private(set) var saved = false
    @Published var issue: String?
    private var directory: ShowerDirectory?
    /// Whose school login `identity` came from: a binding is saved only while that person is
    /// still the one signed in.
    private weak var campus: CampusModel?
    private var personStamp: Int?
    static let personChangedText = "学校账号换了人，重新读取一下宿舍。"

    func reset() {
        identity = nil; options = [[],[],[],[]]; selected = []; machines = []; saved = false; issue = nil
        autoMatched = false; directory = nil; campus = nil; personStamp = nil
    }

    enum AutoBind: Equatable {
        /// Saved: the portal address matched exactly one room with exactly one controller.
        case bound
        /// Hot water isn't available for this account/build: nothing to bind.
        case unavailable
        /// Needs the user: several rooms/controllers, nothing matched, or a read failed (`issue`).
        case needsChoice
    }

    /// First-run guide: the user confirmed the dorm read from the school account. Bind its
    /// controller when the match is unambiguous; otherwise the caller opens the dorm screen.
    func autoBind(campus: CampusModel, water: ShowerModel) async -> AutoBind {
        if water.configured { return .bound }
        guard campus.configured else { return .needsChoice }
        await prepare(campus:campus, water:water)
        if identity == nil && issue == ShowerModel.platformMissingText { return .unavailable }
        guard autoMatched, machines.count == 1, let machine = machines.first else { return .needsChoice }
        await save(machine, water:water)
        return saved ? .bound : .needsChoice
    }

    /// Reads the hot-water identity, then matches the portal dorm address (never guesses).
    func prepare(campus: CampusModel, water: ShowerModel) async {
        guard !busy, campus.configured, water.mayImport else { return }
        reset()
        busy = true
        defer { busy = false }
        do {
            if let profile = water.profile {
                let client = LxtClient(http:AppEnvironment.showerHTTP, profile:profile)
                let stamp = await campus.personStamp()
                let user = try await client.userInfo(campus.showerHandoff())
                identity = user; directory = client; self.campus = campus; personStamp = stamp
                let onboarding = ShowerOnboarding(directory:client)
                if let address = campus.address {
                    apply(try await onboarding.match(address, schoolId:user.schoolId), address:address)
                }
                if options[0].isEmpty { options[0] = try await client.areas(parent:user.schoolId) }
                if selected.isEmpty, options[0].count == 1, let only = options[0].first { busy = false; await choose(only, at:0) }
            } else {
                issue = ShowerModel.platformMissingText
            }
        } catch {
            issue = (error as? ServiceError)?.userMessage ?? "暂时读不到宿舍，稍后再试。"
        }
    }

    private func apply(_ result: ShowerOnboarding.Result, address: DormAddress) {
        switch result {
        case .matched(let path, let machine):
            selected = path; machines = [machine]; autoMatched = true
        case .chooseMachine(let path, let list):
            selected = path; machines = list; autoMatched = true
        case .pick(let level, let list, let path):
            selected = path; options[level.rawValue] = list
        case .noController(let path, let message):
            selected = path; issue = message
        case .addressUnknown(let message):
            issue = message
        }
    }

    func choose(_ option: AreaNode, at level: Int) async {
        guard !busy, selected.count >= level, let directory, let identity else { return }
        autoMatched = false
        selected = Array(selected.prefix(level)) + [option]
        for index in (level+1)..<4 { options[index] = [] }
        machines = []; saved = false; issue = nil; busy = true
        defer { busy = false }
        do {
            if level == 3 {
                switch try await ShowerOnboarding(directory:directory).controllers(path:selected, schoolId:identity.schoolId) {
                case .matched(_, let machine): machines = [machine]
                case .chooseMachine(_, let list): machines = list
                case .noController(_, let message), .addressUnknown(let message): issue = message
                case .pick: issue = ShowerOnboarding.noControllerText
                }
            } else {
                options[level+1] = level + 1 == 3 ? try await directory.rooms(floor:option.id) : try await directory.areas(parent:option.id)
                busy = false
                if options[level+1].count == 1, let only = options[level+1].first { await choose(only, at:level+1) }
            }
        } catch { issue = (error as? ServiceError)?.userMessage ?? "宿舍列表没读到，重新选一下。" }
    }

    func save(_ machine: ShowerMachine, water: ShowerModel) async {
        guard selected.count == 4, let identity, water.mayImport else { return }
        busy = true; defer { busy = false }
        guard let campus, let personStamp, await campus.isSamePerson(since:personStamp) else {
            reset(); issue = Self.personChangedText
            return
        }
        do {
            let binding = ShowerBinding(studentId:identity.studentId, schoolId:identity.schoolId, machineId:machine.machineId,
                                       roomId:selected[3].id, roomLabel:ShowerOnboarding.roomLabel(selected),
                                       machineName:machine.name)
            try water.saveBinding(binding)
            saved = true; issue = nil
        } catch { issue = (error as? ServiceError)?.userMessage ?? "没保存上，再试一次。" }
    }
}
