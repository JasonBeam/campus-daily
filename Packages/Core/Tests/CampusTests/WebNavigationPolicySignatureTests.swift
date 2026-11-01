import XCTest

/// The two school web views keep their host allow-list in WebKit's optional
/// `decidePolicyFor navigationAction` delegate method. A spelling that drifts from the SDK still
/// compiles but is never called, so pin the exact SDK signature in both coordinators (the app
/// also asserts `responds(to:)` when each coordinator is created).
final class WebNavigationPolicySignatureTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// `webView(_:decidePolicyFor:decisionHandler:)` as the iOS SDK declares it in Swift 6.
    static let signature = try! NSRegularExpression(pattern:
        #"funcwebView\(_\w+:WKWebView,decidePolicyFor\w+:WKNavigationAction,decisionHandler:@escaping@MainActor@Sendable\(WKNavigationActionPolicy\)->Void\)\{"#)

    func testBothCoordinatorsImplementTheSDKSignature() throws {
        for path in ["App/Interface/CampusCard/CampusRechargeView.swift", "App/Services/CampusWebLogin/CampusWebLogin.swift"] {
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
