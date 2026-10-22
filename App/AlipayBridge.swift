import Foundation
import AlipaySDK
import WaterCore

@MainActor final class AlipayBridge {
    static let shared = AlipayBridge()
    static let scheme = "com.beamjason.campushotwater.alipay"
    private var completion: ((String, String) -> Void)?
    func openCheckout(_ url: URL, completion: @escaping (Bool) -> Void) {
        guard LaundryPayment.isAllowedCheckoutURL(url) else { completion(false); return }
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
        guard url.scheme == Self.scheme, url.host == "safepay" else { return }
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
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LaundryCache",isDirectory:true)
        let object = ["status":status,"memo":String(memo.prefix(512)),"receivedAt":ISO8601DateFormatter().string(from:Date())]
        if let data = try? JSONSerialization.data(withJSONObject:object) {
            try? data.write(to:folder.appendingPathComponent("last-payment-launch.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
