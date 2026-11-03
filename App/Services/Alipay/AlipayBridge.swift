import Foundation
import AlipaySDK
import UIKit
import Core

@MainActor final class AlipayBridge {
    static let shared = AlipayBridge()
    /// Alipay returns to `<this build's bundle id>.alipay` (Info.plist: `$(PRODUCT_BUNDLE_IDENTIFIER).alipay`),
    /// so two builds with different bundle ids installed side by side each get their own result.
    /// For the default bundle id this is `com.beamjason.xiaorichang.alipay`.
    static let scheme: String = {
        let types = Bundle.main.object(forInfoDictionaryKey:"CFBundleURLTypes") as? [[String:Any]] ?? []
        let declared = types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        let expected = (Bundle.main.bundleIdentifier ?? "com.beamjason.xiaorichang") + ".alipay"
        // Prefer the exact expected value; otherwise whatever .alipay scheme Info.plist declares.
        return declared.first { $0.caseInsensitiveCompare(expected) == .orderedSame }
            ?? declared.first { $0.hasSuffix(".alipay") } ?? expected
    }()
    /// Called once when the SDK reports the payment finished, either from its own web page (no
    /// Alipay installed, the app never left the foreground) or after Alipay returned the app.
    private var returned: (() -> Void)?
    func openCheckout(_ url: URL, completion: @escaping (Bool) -> Void) {
        guard PaymentLaunchPolicy.isAllowedCheckoutURL(url) else { completion(false); return }
        UIApplication.shared.open(url,options:[:]) { opened in
            Task { @MainActor in completion(opened) }
        }
    }
    func pay(_ signed: String, returned: @escaping () -> Void) {
        self.returned = returned
        AlipaySDK.defaultService().payOrder(signed,fromScheme:Self.scheme) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }
    func handle(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare(Self.scheme) == .orderedSame, url.host == "safepay" else { return }
        AlipaySDK.defaultService().processOrder(withPaymentResult:url) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }
    /// The result itself is not used: the order is read from U净 either way.
    private func finish() {
        let callback = returned; returned = nil; callback?()
    }
}

/// `LaundryEngine`'s launcher: only the two checked launch kinds, through AlipayBridge.
struct AlipayPaymentLauncher: PaymentLauncher {
    /// The SDK reported the payment finished: read the order now, without waiting for the app
    /// to become active again (the SDK's own web page never leaves the app).
    let returned: @MainActor @Sendable () -> Void

    func open(_ launch: PayLaunch) async -> Bool {
        switch launch {
        case .query:
            return true
        case .checkout(let url):
            guard PaymentLaunchPolicy.isAllowedCheckoutURL(url) else { return false }
            return await withCheckedContinuation { done in
                Task { @MainActor in AlipayBridge.shared.openCheckout(url) { done.resume(returning:$0) } }
            }
        case .sdk(let order):
            // The SDK switches to Alipay (or shows its own web page); when it reports back
            // (`handle(_:)` or its own completion) the order is read.
            let returned = returned
            await MainActor.run { AlipayBridge.shared.pay(order) { returned() } }
            return true
        }
    }
}
