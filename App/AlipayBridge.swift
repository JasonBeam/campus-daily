import Foundation
import AlipaySDK
import WaterCore

@MainActor final class AlipayBridge {
    enum CheckoutLaunch { case sdk, external, failed }
    static let shared = AlipayBridge()
    static let scheme = "com.beamjason.campushotwater.alipay"
    private var completion: ((String, String) -> Void)?
    private var attemptID: UUID?

    func openCheckout(_ url: URL, onPaymentResult: @escaping (String, String) -> Void,
                      completion: @escaping (CheckoutLaunch) -> Void) {
        guard LaundryPayment.isAllowedCheckoutURL(url) else { completion(.failed); return }
        let conversion = LaundrySDKConversion(callback:onPaymentResult)
        let attempt = prepare { status,memo in conversion.receive(status:status,memo:memo) }
        // Only the official SDK may convert the original service-issued URL. Never rewrite it.
        let converted = AlipaySDK.defaultService().payInterceptor(withUrl:url.absoluteString,fromScheme:Self.scheme) { [weak self] result in
            Task { @MainActor in self?.receive(result,expected:attempt) }
        }
        conversion.resolve(converted:converted)
        if converted {
            record(status:"checkout_sdk_converted",memo:"",route:"sdk-h5")
            completion(.sdk)
            // An SDK error after acceptance must not launch a second checkout.
            return
        }
        if attemptID == attempt { self.completion = nil; attemptID = nil }
        UIApplication.shared.open(url,options:[:]) { opened in
            Task { @MainActor in
                self.record(status:opened ? "checkout_opened" : "checkout_open_failed",memo:"",route:"external")
                completion(opened ? .external : .failed)
            }
        }
    }

    func pay(_ signed: String, completion: @escaping (String, String) -> Void) {
        let attempt = prepare(completion)
        record(status:"sdk_app_requested",memo:"",route:"sdk-app")
        AlipaySDK.defaultService().payOrder(signed,fromScheme:Self.scheme) { [weak self] result in
            Task { @MainActor in self?.receive(result,expected:attempt) }
        }
    }

    func handle(_ url: URL) {
        guard url.scheme == Self.scheme, url.host == "safepay" else { return }
        AlipaySDK.defaultService().processOrder(withPaymentResult:url) { [weak self] result in
            Task { @MainActor in self?.receive(result,expected:nil) }
        }
    }

    private func prepare(_ callback: @escaping (String,String) -> Void) -> UUID {
        let id = UUID(); attemptID = id; completion = callback; return id
    }
    private func receive(_ result: [AnyHashable:Any]?, expected: UUID?) {
        if let expected, expected != attemptID { return }
        let result = LaundrySDKResult(result)
        record(status:result.status,memo:result.memo)
        let callback = completion; completion = nil; attemptID = nil
        callback?(result.status,result.memo)
    }
    private func record(status: String, memo: String, route: String? = nil) {
        let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LaundryCache",isDirectory:true)
        var object = ["status":status,"memo":String(memo.prefix(512)),"receivedAt":ISO8601DateFormatter().string(from:Date())]
        if let route { object["route"] = route }
        if let data = try? JSONSerialization.data(withJSONObject:object) {
            try? data.write(to:folder.appendingPathComponent("last-payment-launch.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            if route != nil {
                try? data.write(to:folder.appendingPathComponent("last-payment-route.json"),options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }
}
