import Foundation

/// The school login and recharge web views enforce their host allow-list in
/// `webView(_:decidePolicyFor:decisionHandler:)`. That method is optional in
/// `WKNavigationDelegate`, so if its Swift spelling stops matching the SDK it still compiles and
/// WebKit simply never calls it. Each coordinator asserts at init that WebKit will find it, and
/// in every build a web view whose delegate would not be asked loads nothing (fail closed).
enum WebNavigationPolicy {
    static let selector = NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")

    /// True when WebKit will ask `delegate` before each navigation.
    static func isEnforced(by delegate: NSObject) -> Bool { delegate.responds(to:selector) }
    /// The same, asked before any web view exists.
    static func isEnforced(by type: NSObject.Type) -> Bool { type.instancesRespond(to:selector) }
}
