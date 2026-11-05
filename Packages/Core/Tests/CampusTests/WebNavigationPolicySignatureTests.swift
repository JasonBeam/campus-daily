import XCTest

/// The school login web view keeps its host allow-list in WebKit's optional
/// `decidePolicyFor navigationAction` delegate method. A spelling that drifts from the SDK still
/// compiles but is never called, so pin the exact SDK signature in its coordinator (the app
/// also asserts `responds(to:)` when the coordinator is created). The top-up web view it was
/// pinned in too is gone: 校园充值 opens the school's pages outside the app.
final class WebNavigationPolicySignatureTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// `webView(_:decidePolicyFor:decisionHandler:)` as the iOS SDK declares it in Swift 6.
    static let signature = try! NSRegularExpression(pattern:
        #"funcwebView\(_\w+:WKWebView,decidePolicyFor\w+:WKNavigationAction,decisionHandler:@escaping@MainActor@Sendable\(WKNavigationActionPolicy\)->Void\)\{"#)

    func testTheLoginCoordinatorImplementsTheSDKSignature() throws {
        for path in ["App/Services/CampusWebLogin/CampusWebLogin.swift"] {
            let source = try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
            let compact = source.filter { !$0.isWhitespace }
            let range = NSRange(compact.startIndex..., in: compact)
            XCTAssertEqual(Self.signature.numberOfMatches(in: compact, range: range), 1, path)
            XCTAssertTrue(compact.contains("assert(responds(to:WebNavigationPolicy.selector)"), path)
        }
    }

    func testPatternRejectsADriftedSpelling() {
        let drifted = "func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {"
            .filter { !$0.isWhitespace }
        XCTAssertEqual(Self.signature.numberOfMatches(in: drifted, range: NSRange(drifted.startIndex..., in: drifted)), 0)
    }
}
