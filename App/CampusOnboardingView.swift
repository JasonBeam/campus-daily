import SwiftUI
import WebKit
import WaterCore

@MainActor private final class CampusBrowserState: ObservableObject {
    weak var webView: WKWebView?
    @Published var issue: String?
    @Published var reading = false
    func read() async throws -> CampusConfig {
        guard !reading, let webView, webView.url?.scheme == "https", webView.url?.host == "ecykt.gdbtu.edu.cn" else { throw OnboardingError.login }
        reading = true; defer { reading = false }
        // Only the official session state is read, on an explicit native button tap.
        // No password fields, form hooks, injected listeners or remote uploads.
        let script = """
        (()=>{if(location.origin!=="https://ecykt.gdbtu.edu.cn")return null;const s=JSON.parse(localStorage.getItem("elecampus_state")||"{}");return JSON.stringify({logintoken:s.logintoken,loginInfo:s.loginInfo,schoolid:s.schoolid,custInfo:s.custInfo,custid:s.custid,userAgent:navigator.userAgent})})()
        """
        guard let raw = try await webView.evaluateJavaScript(script) as? String else { throw OnboardingError.login }
        return try OfficialCampusSession.parse(Data(raw.utf8))
    }
}

private struct OfficialCampusBrowser: UIViewRepresentable {
    @ObservedObject var state: CampusBrowserState
    func makeCoordinator() -> Coordinator { Coordinator(state) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame:.zero,configuration:config)
        view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.isInspectable = false
        state.webView = view
        view.load(URLRequest(url:URL(string:"https://portal.gdbtu.edu.cn/main.html#/Student")!))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: CampusBrowserState
        init(_ state: CampusBrowserState) { self.state = state }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
            guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
            guard let url = navigationAction.request.url,
                  url.scheme == "https", ["portal.gdbtu.edu.cn","cas.gdbtu.edu.cn","ecykt.gdbtu.edu.cn"].contains(url.host ?? ""),
                  url.user == nil, url.password == nil, url.port == nil || url.port == 443 else {
                state.issue = "请使用学校账号密码登录，当前仅支持学校官方页面"
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
               url.scheme == "https", ["portal.gdbtu.edu.cn","cas.gdbtu.edu.cn","ecykt.gdbtu.edu.cn"].contains(url.host ?? "") {
                webView.load(navigationAction.request)
            }
            return nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as? URLError)?.code != .cancelled { state.issue = "学校网页加载失败，请检查网络后重试" }
        }
    }
}

private struct CampusLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = CampusBrowserState()
    let receive: (CampusConfig) -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                Text("登录后，点门户“一卡通信息”旁的“更多”，再读取登录结果。")
                    .font(.footnote).foregroundStyle(.secondary).padding(12)
                OfficialCampusBrowser(state:browser)
                if let issue = browser.issue { Text(issue).font(.footnote).foregroundStyle(.orange).padding(10) }
                Button {
                    Task { do { let config = try await browser.read(); receive(config); dismiss() }
                        catch { browser.issue = (error as? LocalizedError)?.errorDescription ?? "登录信息读取失败，请重试" } }
                } label: { Text(browser.reading ? "正在读取…" : "读取登录结果").frame(maxWidth:.infinity,minHeight:44) }
                    .buttonStyle(.borderedProminent).padding().disabled(browser.reading).accessibilityIdentifier("readCampusLogin")
            }.navigationTitle("学校官方登录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct CampusOnboardingView: View {
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var water: WaterModel
    @State private var login = false
    @State private var draft: CampusConfig?
    @State private var identity: (student: String, school: String)?
    @State private var options: [[DormOption]] = [[],[],[],[]]
    @State private var selected: [DormOption] = []
    @State private var machines: [DormMachine] = []
    @State private var busy = false
    @State private var saved = false
    @State private var issue: String?
    private let provider = DormOnboardingProvider()
    private let levels = ["校区","楼栋","楼层","寝室"]
    var body: some View {
        Form {
            Section {
                Button { login = true } label: { Label(draft == nil ? "登录学校账号" : "重新登录",systemImage:"person.crop.circle") }
                    .accessibilityIdentifier("officialCampusLogin").disabled(busy)
                if draft != nil {
                    Label("已读取校园登录",systemImage:"checkmark.circle").foregroundStyle(.green)
                    Button("保存登录并读取宿舍") { Task { await prepare() } }
                        .disabled(busy || !water.mayImport || campus.loading).accessibilityIdentifier("prepareDormOnboarding")
                }
            } header: { Text("校园登录") } footer: { Text("在学校官方网页输入账号密码。App 只保存登录后的查询凭据，不保存学校密码。") }
            if identity != nil {
                Section("热水宿舍") {
                    ForEach(0..<4,id:\.self) { level in
                        if !options[level].isEmpty {
                            Menu {
                                ForEach(options[level]) { option in
                                    Button(option.name) { Task { await choose(option,at:level) } }
                                }
                            } label: { LabeledContent(levels[level],value:selected.count > level ? selected[level].name : "请选择") }
                                .disabled(busy).accessibilityIdentifier("dormLevel\(level)")
                        }
                    }
                    ForEach(machines) { machine in
                        VStack(alignment:.leading,spacing:10) {
                            Label(machine.name,systemImage:"drop").font(.headline)
                            Text("核对是你的寝室后保存。保存不会出水，也不会更改学校绑定。")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("保存此宿舍") { save(machine) }
                                .disabled(busy || !water.mayImport || campus.loading || saved).accessibilityIdentifier("saveDormBinding")
                        }.padding(.vertical,6)
                    }
                }
            }
            if busy { Section { HStack { ProgressView(); Text("正在读取学校信息…") } } }
            if let issue { Section { Text(issue).foregroundStyle(.orange).font(.footnote) } }
            if saved { Section { Label("宿舍已保存",systemImage:"checkmark.circle.fill").foregroundStyle(.green) } }
        }.navigationTitle("校园登录与宿舍").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$login) { CampusLoginSheet { value in
                draft = value; identity = nil; options = [[],[],[],[]]; selected = []; machines = []; saved = false; issue = nil
            } }
    }
    private func prepare() async {
        guard !busy, let draft, water.mayImport else { return }
        guard let seed = water.onboardingProfile else { issue = OnboardingError.seed.rawValue; return }
        busy = true; issue = nil; saved = false
        defer { busy = false }
        do {
            let who = try await provider.identity(campus:draft,seed:seed)
            let values = try await provider.options(parent:who.school,seed:seed)
            try campus.acceptLogin(draft)
            identity = who; options = [values,[],[],[]]; selected = []; machines = []
        } catch { issue = (error as? LocalizedError)?.errorDescription ?? "暂时无法读取宿舍，请稍后重试" }
    }
    private func choose(_ option: DormOption, at level: Int) async {
        guard !busy, selected.count >= level, let seed = water.onboardingProfile, let identity else { return }
        selected = Array(selected.prefix(level)) + [option]
        for index in (level+1)..<4 { options[index] = [] }
        machines = []; saved = false; issue = nil; busy = true
        defer { busy = false }
        do {
            if level == 3 { machines = try await provider.machines(room:option.id,school:identity.school,seed:seed)
                if machines.isEmpty { issue = "该寝室暂未返回水控，请核对寝室" }
            } else { options[level+1] = try await provider.options(parent:option.id,rooms:level == 2,seed:seed) }
        } catch { issue = (error as? LocalizedError)?.errorDescription ?? "宿舍列表读取失败，请重新选择" }
    }
    private func save(_ machine: DormMachine) {
        guard selected.count == 4, let seed = water.onboardingProfile, let identity, water.mayImport, !campus.loading else { return }
        // Existing model's BLE profile is reused; hardware identity is still checked before every authorization.
        do {
            let value = try seed.configuration(student:identity.student,school:identity.school,machine:machine.id)
            let old = water.onboardingSeed
            try water.acceptDorm(value)
            do { try campus.saveDormName(selected.map(\.name).joined(separator:" · ")) }
            catch { if let old { try water.acceptDorm(old) }; throw error }
            saved = true; issue = nil
            Task { await campus.refresh(force:true) }
        } catch { issue = (error as? LocalizedError)?.errorDescription ?? "保存失败，请重试" }
    }
}
