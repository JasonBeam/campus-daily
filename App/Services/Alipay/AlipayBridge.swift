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
    private var completion: ((String, String) -> Void)?
    func openCheckout(_ url: URL, completion: @escaping (Bool) -> Void) {
        guard PaymentLaunchPolicy.isAllowedCheckoutURL(url) else { completion(false); return }
        UIApplication.shared.open(url,options:[:]) { opened in
            Task { @MainActor in
                self.record(status:opened ? "checkout_opened" : "checkout_open_failed",memo:"")
                completion(opened)
            }
        }
    }
    func pay(_ signed: String, completion: @escaping (String, String) -> Void) {
        self.completion = completion
        AlipaySDK.defaultService().payOrder(signed,fromScheme:Self.scheme) { [weak self] result in
            let values = result as NSDictionary?
            let status = values?["resultStatus"] as? String ?? "unknown"
            let memo = values?["memo"] as? String ?? ""
            Task { @MainActor in self?.finish(status:status,memo:memo) }
        }
    }
    func handle(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare(Self.scheme) == .orderedSame, url.host == "safepay" else { return }
        AlipaySDK.defaultService().processOrder(withPaymentResult:url) { [weak self] result in
            let values = result as NSDictionary?
            let status = values?["resultStatus"] as? String ?? "unknown"
            let memo = values?["memo"] as? String ?? ""
            Task { @MainActor in self?.finish(status:status,memo:memo) }
        }
    }
    private func finish(status: String, memo: String) {
        record(status:status,memo:memo)
        let callback = completion; completion = nil; callback?(status,memo)
    }
    private func record(status: String, memo: String) {
        #if DEBUG
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LaundryCache",isDirectory:true)
        let object = ["status":status,"memo":String(memo.prefix(512)),"receivedAt":ISO8601DateFormatter().string(from:Date())]
        if let data = try? JSONSerialization.data(withJSONObject:object) {
            try? data.write(to:folder.appendingPathComponent("last-payment-launch.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
        #endif
    }
}

/// `LaundryEngine`'s launcher: only the two checked launch kinds, through AlipayBridge.
struct AlipayPaymentLauncher: PaymentLauncher {
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
            // The SDK switches to Alipay (or its own web page); the result comes back through
            // `handle(_:)`, and the engine reads the order when the app is active again.
            await MainActor.run { AlipayBridge.shared.pay(order) { _, _ in } }
            return true
        }
    }
}
