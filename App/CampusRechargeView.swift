import SwiftUI
import WebKit
import WaterCore

enum CampusRechargeKind: String, Identifiable {
    case card, power
    var id: String { rawValue }
    var title: String { self == .card ? "校园卡充值" : "宿舍电费充值" }
}

struct CampusRechargeView: View {
    @EnvironmentObject private var campus: CampusModel
    let kind: CampusRechargeKind
    @State private var context: CampusWebSession?
    @State private var issue: String?
    @State private var loading = false
    @State private var login = false
    @State private var revision = UUID()
    var body: some View {
        VStack(spacing:0) {
            Text("学校官方充值页面 · 请核对账户、寝室和金额后付款")
                .font(.footnote).foregroundStyle(.secondary).padding(12)
            if let context {
                CampusRechargeBrowser(context:context,power:kind == .power) { issue = "网页登录已过期，请重新登录学校账号" }
                    .id(revision)
            } else if loading {
                ProgressView("正在确认学校登录…").frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ContentUnavailableView("暂时无法打开充值",systemImage:"person.crop.circle",
                    description:Text(issue ?? "请先登录学校账号"))
            }
            if let issue {
                Text(issue).font(.footnote).foregroundStyle(.orange).padding(.horizontal)
                Button("重新登录学校账号") { login = true }.buttonStyle(.borderedProminent).padding()
            }
        }.background(NativeTheme.background).tint(NativeTheme.tint)
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("重试") { revision = UUID() }.disabled(loading) } }
            .task(id:revision) { await prepare() }
            .sheet(isPresented:$login) {
                CampusLoginSheet { value in
                    do { try campus.acceptLogin(value); revision = UUID() }
                    catch { issue = "登录信息暂时无法保存，请稍后重试" }
                }
            }
    }
    private func prepare() async {
        context = nil; issue = nil; loading = true
        defer { loading = false }
        guard let config = campus.onboardingLogin else { issue = "请先登录学校账号"; return }
        do {
            let result = try await CampusProvider().webSession(config:config)
            try Task.checkCancellation()
            guard campus.onboardingLogin?.cacheIdentity == config.cacheIdentity,
                  campus.onboardingLogin?.accToken == config.accToken else { throw CampusError.expired }
            context = result
        } catch is CancellationError { }
          catch { issue = (error as? CampusError) == .expired ? "校园登录已过期，请重新登录学校账号" : (error as? LocalizedError)?.errorDescription ?? "学校页面暂时无法打开，请重试" }
    }
}

private struct CampusRechargeBrowser: UIViewRepresentable {
    let context: CampusWebSession
    let power: Bool
    let expired: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(expired:expired) }
    func makeUIView(context bridge: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A separate recharge store prevents this context overwriting the official login browser.
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(source:context.bootstrapScript,injectionTime:.atDocumentStart,forMainFrameOnly:true))
        configuration.userContentController.add(bridge.coordinator,name:"campusRechargeExpired")
        let expiryScript = """
        (()=>{if(location.hostname!=='ecykt.gdbtu.edu.cn')return;
        let sent=false;function check(){if(!sent&&document.body&&/登录状态过期|登录已过期|登录失效/.test(document.body.innerText)){sent=true;window.webkit.messageHandlers.campusRechargeExpired.postMessage('expired')}}
        new MutationObserver(check).observe(document.documentElement,{childList:true,subtree:true});check()})();
        """
        configuration.userContentController.addUserScript(WKUserScript(source:expiryScript,injectionTime:.atDocumentEnd,forMainFrameOnly:true))
        let view = WKWebView(frame:.zero,configuration:configuration)
        view.navigationDelegate = bridge.coordinator; view.uiDelegate = bridge.coordinator
        view.isInspectable = false
        if !context.userAgent.isEmpty { view.customUserAgent = context.userAgent }
        view.load(URLRequest(url:context.rechargeURL(power:power)))
        return view
    }
    func updateUIView(_ view: WKWebView,context: Context) {}
    static func dismantleUIView(_ view: WKWebView,coordinator: Coordinator) {
        view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName:"campusRechargeExpired")
        view.navigationDelegate = nil; view.uiDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let expired: () -> Void
        init(expired: @escaping () -> Void) { self.expired = expired }
        func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
            if message.name == "campusRechargeExpired", message.frameInfo.isMainFrame,
               message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == "ecykt.gdbtu.edu.cn",
               message.body as? String == "expired" { expired() }
        }
        func webView(_ webView: WKWebView,decidePolicyFor action: WKNavigationAction,decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
            guard action.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "https", ["ecykt.gdbtu.edu.cn","portal.gdbtu.edu.cn","cas.gdbtu.edu.cn"].contains(url.host ?? ""),
               url.user == nil, url.password == nil, url.port == nil || url.port == 443 { decisionHandler(.allow); return }
            if action.navigationType == .linkActivated, webView.url?.host == "ecykt.gdbtu.edu.cn",
               ["alipays","alipay","weixin"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }
        func webView(_ webView: WKWebView,createWebViewWith configuration: WKWebViewConfiguration,for action: WKNavigationAction,windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, action.request.url?.scheme == "https", action.request.url?.host == "ecykt.gdbtu.edu.cn" { webView.load(action.request) }
            return nil
        }
    }
}
