import XCTest
import Core
@testable import XiaoRiChang

/// A sign-in still waiting for the school when 退出登录 and a new sign-in of the same account
/// overtake it. Its late failure was caused by them, not by writes of its own: the new sign-in's
/// hot-water binding and numbers stay, and nothing asks for the dorm to be checked again.
@MainActor
final class StaleSchoolSignInTests: XCTestCase {
    /// The school: the first card check is held until `release()`; every later one answers that
    /// the card is bound. Anything else is offline.
    private final class HeldCardCheck: HTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var checks = 0
        private var released = false
        private var waiting: CheckedContinuation<Void, Never>?

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            guard request.url.path.hasSuffix("/getSysBindCustInfo") else { throw ServiceError.offline }
            let first = lock.withLock { () -> Bool in defer { checks += 1 }; return checks == 0 }
            if first {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    let go = lock.withLock { () -> Bool in
                        if released { return true }
                        waiting = c; return false
                    }
                    if go { c.resume() }
                }
            }
            let body = #"{"code":0,"msg":"获取成功","data":[{"custid":"SYNTHETIC-CUST","custunionid":"SYNTHETIC-CARD-1","custname":"测试员"}]}"#
            return HTTPResponse(status:200, headers:["Content-Type":"application/json"], body:Data(body.utf8))
        }

        /// True once the first check is held; false after about two seconds without it.
        func reached() async -> Bool {
            for _ in 0..<200 where !lock.withLock({ waiting != nil }) { try? await Task.sleep(for:.milliseconds(10)) }
            return lock.withLock { waiting != nil }
        }

        func release() {
            let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                released = true; defer { waiting = nil }; return waiting
            }
            c?.resume()
        }
    }

    /// The official page's `elecampus_state`, synthetic.
    private static let webLogin = CampusWebLogin(state:Data(#"""
        {"logintoken":"SYNTHETIC-TOKEN","schoolid":"450010","loginInfo":{"syscustid":"SYNTHETIC-SYS","token":"SYNTHETIC-TOKEN"},"custInfo":{"custid":"SYNTHETIC-CUST","custunionid":"SYNTHETIC-CARD-1"}}
        """#.utf8), dormAddress:"")

    func testAnOvertakenSignInThatFailsLeavesTheNewSignInAlone() async throws {
        let store = ScriptedStore()
        let http = HeldCardCheck()
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:http, showerHTTP:SampleHTTPClient(), laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:SampleShowerTransport(), leaseFile:nil,
                                      applicationSupport:nil, sharedDidChange:{})
        try services.schoolVault.saveEcyktSession(EcyktSession(token:"SYNTHETIC-OLD", syscustid:"SYNTHETIC-SYS", cardUnionID:"SYNTHETIC-CARD-1"))
        let reminders = Reminders.sample(defaults:services.defaults)
        let shower = ShowerModel(services:services, reminders:reminders, activities:nil, gate:LiveShowerGate())
        let campus = CampusModel(services:services, stack:services.schoolStack(), reminders:reminders) { shower }
        await waitUntil { shower.profileLoaded }

        let first = Task { try await campus.adoptWebState(Self.webLogin) }
        let held = await http.reached()
        XCTAssertTrue(held, "the first sign-in waits for the school")

        campus.signOut()
        try await campus.adoptWebState(Self.webLogin)
        try shower.saveBinding(Fixture.binding)
        await waitUntil { shower.gateRecord != .notLoaded }
        let numbers = HomeSnapshot(card:Tile(value:Money(fen:790), fetchedAt:Date(timeIntervalSince1970:1_793_000_000)), roomLabel:"99栋 991")
        try SharedSnapshotStore(store:store).saveSnapshot(numbers)
        campus.reload()
        XCTAssertEqual(campus.snapshot, numbers)

        http.release()
        let result = await first.result
        if case .success = result { XCTFail("the first sign-in was overtaken") }

        XCTAssertEqual(try services.showerVault.binding(), Fixture.binding)
        XCTAssertEqual(shower.binding, Fixture.binding)
        XCTAssertFalse(shower.residenceReviewRequired)
        XCTAssertEqual(try SharedSnapshotStore(store:store).loadSnapshot(), numbers)
        XCTAssertEqual(campus.snapshot, numbers)
        XCTAssertNil(campus.switchNotice)
    }
}
