import SwiftUI
import WebKit
import Core

/// What the official pages produced: the ecykt `elecampus_state` (selected fields) and the
/// portal's dorm address line. Handed to `CampusModel.adoptWebState`.
struct CampusWebLogin {
    var state: Data
    var dormAddress: String
}

@MainActor final class CampusBrowserState: ObservableObject {
    weak var webView: WKWebView?
    @Published var issue: String?
    @Published var reading = false
    @Published var status = "填写学校学工号和密码，登录后自动同步校园卡。"
    /// Hidden-page phases and their stage line (Core, unit-tested).
    @Published var progress = CampusLoginProgress()
    @Published var now = Date()
    var portalDormAddress = ""
    @Published var connected: CampusWebLogin?
    @Published var stalled = false
    var retry: (() -> Void)?
    func read() async throws -> CampusWebLogin {
        guard !reading, let webView, webView.url?.scheme == "https", webView.url?.host == "ecykt.gdbtu.edu.cn" else { throw ServiceError.malformed(.ecykt, "page") }
        reading = true; defer { reading = false }
        // Only the official wallet session is read in the user-started sign-in flow.
        // No password fields, form hooks, injected listeners or remote uploads.
        let script = """
        (()=>{if(location.origin!=="https://ecykt.gdbtu.edu.cn")return null;const s=JSON.parse(localStorage.getItem("elecampus_state")||"{}");return JSON.stringify({logintoken:s.logintoken,loginInfo:s.loginInfo,schoolid:s.schoolid,custInfo:s.custInfo,custid:s.custid,userAgent:navigator.userAgent})})()
        """
        guard let raw = try await webView.evaluateJavaScript(script) as? String, raw.utf8.count <= 65536 else {
            throw ServiceError.malformed(.ecykt, "elecampus_state")
        }
        return CampusWebLogin(state:Data(raw.utf8), dormAddress:portalDormAddress)
    }
}

struct OfficialCampusBrowser: UIViewRepresentable {
    @ObservedObject var state: CampusBrowserState
    /// DEBUG demo: nothing is loaded (loading-state screenshots).
    var loads = true
    func makeCoordinator() -> Coordinator { Coordinator(state) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame:.zero,configuration:config)
        view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.isInspectable = false
        state.webView = view
        state.retry = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }; coordinator?.connect(view)
        }
        var login = URLComponents(string:"https://cas.gdbtu.edu.cn/cas/login")!
        login.queryItems = [URLQueryItem(name:"service",value:"https://portal.gdbtu.edu.cn/?path=https%3A%2F%2Fportal.gdbtu.edu.cn%2Fmain.html%23%2FStudent")]
        guard WebNavigationPolicy.isEnforced(by:context.coordinator) else {
            let state = state
            Task { @MainActor in state.stalled = true; state.issue = "学校网页暂时打不开，更新校日常后再试。" }
            return view
        }
        if loads { view.load(URLRequest(url:login.url!)) }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let concealed = state.progress.concealed && !state.stalled
        uiView.alpha = concealed ? 0 : 1
        uiView.isUserInteractionEnabled = !concealed
        uiView.accessibilityElementsHidden = concealed
    }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stop(); uiView.stopLoading()
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: CampusBrowserState
        private var automation: Task<Void,Never>?
        init(_ state: CampusBrowserState) {
            self.state = state
            super.init()
            assert(responds(to:WebNavigationPolicy.selector), "WebKit no longer calls the navigation allow-list")
        }
        func stop() { automation?.cancel(); automation = nil }
        func connect(_ webView: WKWebView) {
            stop(); state.stalled = false; state.issue = nil
            guard let file = Bundle.main.url(forResource:"CampusLoginAutomation",withExtension:"js"),
                  let script = try? String(contentsOf:file,encoding:.utf8) else {
                state.stalled = true; state.issue = "自动连接暂时用不了，换备用方式登录。"; return
            }
            automation = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                for _ in 0..<80 {
                    if Task.isCancelled || self.state.connected != nil { return }
                    do {
                        if let raw = try await webView.evaluateJavaScript(script) as? String,
                           let bytes = raw.data(using:.utf8),
                           let result = try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                           let stage = result["stage"] as? String {
                            if Task.isCancelled { return }
                            self.state.progress.probed(automation:stage, formVisible:result["form"] as? Bool == true)
                            switch stage {
                            case "portal-profile":
                                if webView.url?.host == "portal.gdbtu.edu.cn", let address = result["dormAddress"] as? String,
                                   address.count <= 128, address.rangeOfCharacter(from:.controlCharacters) == nil,
                                   let bytes = try? JSONSerialization.data(withJSONObject:address,options:.fragmentsAllowed),
                                   let quoted = String(data:bytes,encoding:.utf8) {
                                    self.state.portalDormAddress = address
                                    _ = try? await webView.evaluateJavaScript("window.__campusDormAcknowledged=" + quoted)
                                }
                            case "login": self.state.status = "填写学校学工号和密码，登录后自动同步校园卡。"
                            case "wallet-ready":
                                if let config = try? await self.state.read(), !Task.isCancelled { self.state.connected = config; return }
                            case "unsupported-entry", "unsupported-origin":
                                self.state.stalled = true; self.state.status = "自动连接尚未完成，可重试或使用备用方式"
                            default: break
                            }
                        }
                    } catch { if Task.isCancelled { return } }
                    try? await Task.sleep(nanoseconds:750_000_000)
                }
                if !Task.isCancelled { self.state.stalled = true }
            }
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            stop()
            if webView.url?.host == "cas.gdbtu.edu.cn" {state.portalDormAddress = ""}
            state.progress.pageStarted(host:webView.url?.host)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { connect(webView) }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy)->Void) {
            let mainFrame = navigationAction.targetFrame?.isMainFrame != false
            guard let url = navigationAction.request.url, SchoolLoginNavigation.allows(url, isMainFrame:mainFrame) else {
                // A blocked frame leaves the page usable; only a blocked page needs the notice.
                if mainFrame { state.issue = "用学校账号密码登录，目前只支持学校官方页面。" }
                decisionHandler(.cancel); return
            }
            guard mainFrame else { decisionHandler(.allow); return }
            if url.host == "cas.gdbtu.edu.cn" {state.portalDormAddress = ""}
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
               SchoolLoginNavigation.allows(url, isMainFrame:true) {
                webView.load(navigationAction.request)
            }
            return nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as? URLError)?.code != .cancelled { state.issue = "学校网页没打开，检查一下网络再试。"; state.progress.failed() }
        }
    }
}
