import XCTest
@testable import WaterCore

private actor ChannelLoader {
    private(set) var calls = 0
    func load(fail: Bool = false) async throws -> LaundryPaymentMethods {
        calls += 1
        await Task.yield()
        if fail { throw LaundryError.network }
        return try JSONDecoder().decode(LaundryPaymentMethods.self,from:Data(#"{"channels":[{"channel":"alipayF2F","branchType":0}]}"#.utf8))
    }
}

final class LaundryPaymentCacheTests: XCTestCase {
    private func config(token: String = "fixture") -> LaundryConfig {
        LaundryConfig(headers:["Authorization":token],qrCode:"fixture-qr",deviceId:"fixture-device")
    }
    func testConcurrentPreparationAndPaymentShareChannelLookup() async throws {
        let cache = LaundryPaymentMethodsCache(); let loader = ChannelLoader(); let config = config()
        async let first = cache.value(config:config,id:"12345") { try await loader.load() }
        async let second = cache.value(config:config,id:"12345") { try await loader.load() }
        let values = try await (first,second)
        XCTAssertEqual(values.0.preferred?.channel,"alipayF2F")
        XCTAssertEqual(values.1.preferred?.channel,"alipayF2F")
        let calls = await loader.calls; XCTAssertEqual(calls,1)
    }
    func testChannelCacheExpiresAfterFortyFiveSeconds() async throws {
        let cache = LaundryPaymentMethodsCache(); let loader = ChannelLoader(); let t = Date()
        for seconds in [0.0,44.0,45.0] {
            _ = try await cache.value(config:config(),id:"12345",now:t.addingTimeInterval(seconds)) { try await loader.load() }
        }
        let calls = await loader.calls; XCTAssertEqual(calls,2)
    }
    func testDifferentOrderAndCredentialsCannotReuseChannels() async throws {
        let cache = LaundryPaymentMethodsCache(); let loader = ChannelLoader()
        _ = try await cache.value(config:config(),id:"12345") { try await loader.load() }
        _ = try await cache.value(config:config(),id:"67890") { try await loader.load() }
        _ = try await cache.value(config:config(token:"changed"),id:"67890") { try await loader.load() }
        let calls = await loader.calls; XCTAssertEqual(calls,3)
    }
    func testFailedPreparationIsRetriedByExplicitPayment() async throws {
        let cache = LaundryPaymentMethodsCache(); let loader = ChannelLoader()
        do {
            _ = try await cache.value(config:config(),id:"12345") { try await loader.load(fail:true) }
            XCTFail()
        } catch {}
        _ = try await cache.value(config:config(),id:"12345") { try await loader.load() }
        let calls = await loader.calls; XCTAssertEqual(calls,2)
    }
}
