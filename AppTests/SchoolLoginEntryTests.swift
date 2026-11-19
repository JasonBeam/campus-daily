import SwiftUI
import UIKit
import WebKit
import XCTest
import Core
@testable import XiaoRiChang

/// Signed out, the ways into a school login open the account-and-password form, not the
/// school's web page: 学校账号与宿舍 opening by itself (暖橙 设置 › 热水, 清爽 宿舍设置, 洗澡页),
/// its 「登录并连接校园卡」 and 导入热水配置. The web login is only the small link on the form.
@MainActor
final class SchoolLoginEntryTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.rootViewController?.dismiss(animated:false)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    /// A signed-out graph on in-memory services: nothing real is read or sent.
    private func graph(theme: AppTheme) -> CampusGraph {
        let http = SampleHTTPClient()
        let services = CampusServices(kind:.live, secureStore:InMemorySecureStore(), defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:http, showerHTTP:http, laundryHTTP:http, feedbackHTTP:nil,
                                      showerTransport:SampleShowerTransport(), leaseFile:nil, applicationSupport:nil, sharedDidChange:{})
        return CampusGraph.sample(on:services, theme:theme)
    }

    private func host<Content: View>(_ content: Content, graph: CampusGraph) {
        let sample = SampleMode(gate:LiveShowerGate(record:{ .known(.idle) }))
        let root = content
            .environment(\.appTheme, graph.theme.theme)
            .environmentObject(graph.shower).environmentObject(graph.campus).environmentObject(graph.laundry)
            .environmentObject(graph.reminders).environmentObject(graph.resetter)
            .environment(graph.theme).environment(sample).environment(SampleAlertStack())
            .environment(\.campusServices, graph.services)
            .defaultAppStorage(graph.services.defaults)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene:$0) } ?? UIWindow(frame:UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView:root)
        window.makeKeyAndVisible()
        self.window = window
    }

    private var presented: UIViewController? { window?.rootViewController?.presentedViewController }

    func testTheDormPageOpensThePasswordFormWhenSignedOut() async {
        for theme in [AppTheme.warm, .clear] {
            let g = graph(theme:theme)
            XCTAssertFalse(g.campus.configured)
            host(NavigationStack { CampusOnboardingView() }, graph:g)
            await waitUntil { self.presented != nil }
            await pause(800)
            let sheet = try? XCTUnwrap(presented?.view, "\(theme): a login sheet opened")
            XCTAssertTrue(sheet.map { Self.views(in:$0).contains { ($0 as? UITextField)?.isSecureTextEntry == true } } ?? false,
                          "\(theme): the password field")
            XCTAssertFalse(sheet.map { Self.views(in:$0).contains { $0 is WKWebView } } ?? true, "\(theme): not the web page")
            await tearDownWindow()
        }
    }

    /// 「登录并连接校园卡」 and 导入热水配置 take the same sheet; the page opens it once by itself.
    func testTheButtonAndTheImportOpenThePasswordFormToo() {
        XCTAssertTrue(CampusOnboardingView.opensLoginOnOpen(configured:false, offered:false))
        XCTAssertFalse(CampusOnboardingView.opensLoginOnOpen(configured:false, offered:true))
        XCTAssertFalse(CampusOnboardingView.opensLoginOnOpen(configured:true, offered:false))
        XCTAssertTrue(CampusOnboardingView.opensLoginAfterImport(configured:false))
        XCTAssertFalse(CampusOnboardingView.opensLoginAfterImport(configured:true))
    }

    /// The web page's debug lines: opened, then completed or cancelled (never both).
    func testTheWebPageClosingSaysCancelledOnlyWithoutASignIn() {
        XCTAssertEqual(CampusLoginSheet.closingEvent(delivered:false), .cancelled)
        XCTAssertNil(CampusLoginSheet.closingEvent(delivered:true))
    }

    private func tearDownWindow() async {
        window?.rootViewController?.dismiss(animated:false)
        await pause(300)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in:$0) }
    }
}
