import SwiftUI
import WebKit
import Core

enum CampusRechargeKind: String, Identifiable {
    case card, power
    var id: String { rawValue }
    var title: String { self == .card ? "校园卡充值" : "宿舍电费充值" }
    var school: RechargeKind { self == .card ? .card : .electricity }
}

struct CampusRechargeView: View {
    @EnvironmentObject private var campus: CampusModel
    let kind: CampusRechargeKind
    @State private var context: RechargeWebSession?
    @State private var issue: RechargeOpenIssue?
    @State private var loading = false
    @State private var login = false
    @State private var revision = UUID()
    /// DEBUG demo: show the state of a web view that can't enforce its allow-list.
    var demoBlocked = false
    /// Without the navigation allow-list the page would load nothing; say so instead of a blank page.
    private var pageBlocked: Bool { demoBlocked || !WebNavigationPolicy.isEnforced(by:CampusRechargeBrowser.Coordinator.self) }
    static let blockedText = "充值页现在打不开，过会儿再试。急用的话，先去学校官网充值。"
    var body: some View {
        VStack(spacing:0) {
            Text("学校官方充值页面 · 付款前核对账户、宿舍和金额")
                .font(.footnote).foregroundStyle(.secondary).padding(12)
            if pageBlocked {
                WebPageUnavailable(text:Self.blockedText) { revision = UUID() }
            } else if let context {
                CampusRechargeBrowser(context:context) { issue = RechargeOpenIssue(text:"学校登录过期了，重新登录一下。") }
                    .id(revision)
            } else if loading {
                ProgressView("正在确认学校登录…").frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ContentUnavailableView("暂时无法打开充值",systemImage:"person.crop.circle",
                    description:Text(issue?.text ?? "先登录学校账号。"))
            }
            if let issue, !pageBlocked {
                Text(issue.text).font(.footnote).foregroundStyle(.orange).padding(.horizontal)
                if issue.offersSignIn {
                    Button("重新登录学校账号") { login = true }.buttonStyle(.borderedProminent).padding()
                }
            }
        }.background(NativeTheme.background).tint(NativeTheme.tint)
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("重试") { revision = UUID() }.disabled(loading) } }
            .task(id:revision) { await prepare() }
            // Account and password first, the school's web page as the fallback.
            .sheet(isPresented:$login) { SchoolReloginSheet { revision = UUID() } }
    }
    private func prepare() async {
        context = nil; issue = nil; loading = true
        defer { loading = false }
        guard campus.configured else { issue = RechargeOpenIssue(text:"先登录学校账号。"); return }
        do {
            let result = try await campus.rechargeSession(kind.school)
            try Task.checkCancellation()
            context = result
        } catch is CancellationError { }
          catch {
            // Only a real expiry says 「过期」; other refusals show what the school said, and a
            // refresh in progress asks to wait without offering a sign-in.
            issue = RechargeOpenIssue(error)
        }
    }
}

private struct CampusRechargeBrowser: UIViewRepresentable {
    let context: RechargeWebSession
    let expired: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(expired:expired) }
    func makeUIView(context bridge: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A separate recharge store prevents this context overwriting the official login browser.
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(source:context.userScript,injectionTime:.atDocumentStart,forMainFrameOnly:true))
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
        // Without the allow-list nothing loads; the page simply stays blank.
        guard WebNavigationPolicy.isEnforced(by:bridge.coordinator) else { return view }
        view.load(URLRequest(url:context.startURL))
        return view
    }
    func updateUIView(_ view: WKWebView,context: Context) {}
    static func dismantleUIView(_ view: WKWebView,coordinator: Coordinator) {
        view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName:"campusRechargeExpired")
        view.navigationDelegate = nil; view.uiDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let expired: () -> Void
        init(expired: @escaping () -> Void) {
            self.expired = expired
            super.init()
            assert(responds(to:WebNavigationPolicy.selector), "WebKit no longer calls the navigation allow-list")
        }
        func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
            if message.name == "campusRechargeExpired", message.frameInfo.isMainFrame,
               message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == "ecykt.gdbtu.edu.cn",
               message.body as? String == "expired" { expired() }
        }
        func webView(_ webView: WKWebView,decidePolicyFor action: WKNavigationAction,decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy)->Void) {
            let mainFrame = action.targetFrame?.isMainFrame != false
            guard let url = action.request.url, url.user == nil, url.password == nil, url.port == nil || url.port == 443 else {
                if let url = action.request.url { ShowerDiagnosticReport.record(RechargeNavigation.blockedEvent(url)) }
                decisionHandler(.cancel); return
            }
            switch RechargeNavigation.decide(url, isUserTap:action.navigationType == .linkActivated, sourceHost:webView.url?.host, isMainFrame:mainFrame) {
            case .allow: decisionHandler(.allow)
            case .openExternal: UIApplication.shared.open(url); decisionHandler(.cancel)
            case .cancel:
                // Scheme and host only (never the path or query), kept in the diagnostics the user
                // can export, so it shows which payment page the school sent to.
                ShowerDiagnosticReport.record(RechargeNavigation.blockedEvent(url))
                decisionHandler(.cancel)
            }
        }
        func webView(_ webView: WKWebView,createWebViewWith configuration: WKWebViewConfiguration,for action: WKNavigationAction,windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, action.request.url?.scheme == "https", action.request.url?.host == "ecykt.gdbtu.edu.cn" { webView.load(action.request) }
            else if let url = action.request.url { ShowerDiagnosticReport.record(RechargeNavigation.blockedEvent(url)) }
            return nil
        }
    }
}

/// A web page that can't be shown: centred icon, one sentence, 「再试一次」.
struct WebPageUnavailable: View {
    let text: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing:14) {
            Image(systemName:"exclamationmark.circle").font(.system(size:28)).foregroundStyle(Theme.ink2)
                .accessibilityHidden(true)
            Text(text).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).fixedSize(horizontal:false, vertical:true)
            Button(action:retry) {
                Text("再试一次").scaledFont(17, .semibold, relativeTo:.headline).foregroundStyle(Theme.pillInk)
                    .padding(.horizontal,32).frame(minHeight:52)
                    .background(Theme.pill, in:Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top,10)
            .accessibilityIdentifier("webPageRetry")
        }
        .padding(.horizontal,40)
        .frame(maxWidth:.infinity, maxHeight:.infinity)
    }
}
