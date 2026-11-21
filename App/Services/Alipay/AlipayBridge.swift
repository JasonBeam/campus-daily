//
//  AlipayBridge.swift
//  XiaoRiChang
//
//  Created by @JasonBeam on 2026/10/22.
//

import Foundation
import AlipaySDK
import UIKit
import Core

/// The AlipaySDK calls the bridge makes (a test's own stands in). Results are not passed on:
/// a callback is only a reason to read the order from U净.
/// Its callbacks may come on any thread.
protocol AlipayService {
    func payOrder(_ order: String, scheme: String, callback: @escaping @Sendable () -> Void)
    /// True when the SDK took the link over (it then shows Alipay or its own page).
    func payInterceptor(_ url: String, scheme: String, callback: @escaping @Sendable () -> Void) -> Bool
    func processOrder(_ url: URL, callback: @escaping @Sendable () -> Void)
}

@MainActor protocol URLOpening {
    func open(_ url: URL, completion: @escaping (Bool) -> Void)
}

struct LiveAlipayService: AlipayService {
    func payOrder(_ order: String, scheme: String, callback: @escaping @Sendable () -> Void) {
        AlipaySDK.defaultService().payOrder(order, fromScheme:scheme) { _ in callback() }
    }
    func payInterceptor(_ url: String, scheme: String, callback: @escaping @Sendable () -> Void) -> Bool {
        AlipaySDK.defaultService().payInterceptor(withUrl:url, fromScheme:scheme) { _ in callback() }
    }
    func processOrder(_ url: URL, callback: @escaping @Sendable () -> Void) {
        AlipaySDK.defaultService().processOrder(withPaymentResult:url) { _ in callback() }
    }
}

struct LiveURLOpener: URLOpening {
    func open(_ url: URL, completion: @escaping (Bool) -> Void) {
        Task { completion(await UIApplication.shared.open(url, options:[:])) }
    }
}

@MainActor final class AlipayBridge {
    static let shared = AlipayBridge(sdk:LiveAlipayService(), opener:LiveURLOpener())
    /// Alipay returns to `<this build's bundle id>.alipay` (Info.plist: `$(PRODUCT_BUNDLE_IDENTIFIER).alipay`),
    /// so two builds with different bundle ids installed side by side each get their own result.
    /// For the default bundle id this is `org.zaxh.xiaorichang.alipay`.
    static let scheme: String = {
        let types = Bundle.main.object(forInfoDictionaryKey:"CFBundleURLTypes") as? [[String:Any]] ?? []
        let declared = types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        let expected = (Bundle.main.bundleIdentifier ?? "org.zaxh.xiaorichang") + ".alipay"
        // Prefer the exact expected value; otherwise whatever .alipay scheme Info.plist declares.
        return declared.first { $0.caseInsensitiveCompare(expected) == .orderedSame }
            ?? declared.first { $0.hasSuffix(".alipay") } ?? expected
    }()

    private let sdk: AlipayService
    private let opener: URLOpening
    /// Which attempt is current and whether its one callback may go out.
    private var gate = PaymentCallbackGate()
    /// The current attempt's order read, called at most once.
    private var returned: (() -> Void)?

    init(sdk: AlipayService, opener: URLOpening) {
        self.sdk = sdk; self.opener = opener
    }

    /// A checked link: the SDK's interceptor gets the original string first. Taken over, nothing
    /// else opens, even if the SDK fails later; declined, the same link opens outside once.
    func openCheckout(_ url: URL, returned: @escaping () -> Void, completion: @escaping (Bool) -> Void) {
        guard PaymentLaunchPolicy.isAllowedCheckoutURL(url) else { completion(false); return }
        let id = gate.begin(takenOver:false)
        self.returned = returned
        let tookOver = sdk.payInterceptor(url.absoluteString, scheme:Self.scheme) { [weak self] in
            Task { @MainActor in self?.receive(id) }
        }
        if gate.resolve(id, takenOver:tookOver) { finish() }
        if tookOver { completion(true); return }
        self.returned = nil
        opener.open(url, completion:completion)
    }

    /// A checked signed order: the SDK switches to Alipay or shows its own page.
    func pay(_ signed: String, returned: @escaping () -> Void) {
        let id = gate.begin(takenOver:true)
        self.returned = returned
        sdk.payOrder(signed, scheme:Self.scheme) { [weak self] in
            Task { @MainActor in self?.receive(id) }
        }
    }

    /// Alipay's return URL. Which attempt it belongs to can't be told, so it never stands for
    /// one's callback: the SDK gets it while the current attempt is the SDK's, and the caller
    /// reads the order (`XiaoRiChangApp.answer`).
    func handle(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare(Self.scheme) == .orderedSame, url.host == "safepay",
              gate.acceptsReturnURL else { return }
        sdk.processOrder(url) { }
    }

    private func receive(_ id: UUID) {
        if gate.receive(id) == .deliver { finish() }
    }

    private func finish() {
        let callback = returned; returned = nil; callback?()
    }
}

/// `LaundryEngine`'s launcher: only the two checked launch kinds, through AlipayBridge.
struct AlipayPaymentLauncher: PaymentLauncher {
    /// The SDK reported back: read the order now, without waiting for the app to become active
    /// again (the SDK's own web page never leaves the app). Not a payment result.
    let returned: @MainActor @Sendable () -> Void

    func open(_ launch: PayLaunch) async -> Bool {
        switch launch {
        case .query:
            return true
        case .checkout(let url):
            guard PaymentLaunchPolicy.isAllowedCheckoutURL(url) else { return false }
            let returned = returned
            return await withCheckedContinuation { done in
                Task { @MainActor in
                    AlipayBridge.shared.openCheckout(url, returned:{ returned() }) { done.resume(returning:$0) }
                }
            }
        case .sdk(let order):
            let returned = returned
            await MainActor.run { AlipayBridge.shared.pay(order) { returned() } }
            return true
        }
    }
}
