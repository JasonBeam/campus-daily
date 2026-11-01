import XCTest
import Core

/// Cancelled recharge navigations are logged by host only.
final class RechargeBlockedHostTests: XCTestCase {
    func testOnlyTheHostIsLogged() {
        let url = URL(string: "https://pay.example.invalid:443/cashier/index.html?orderId=99001&token=SYNTH-SECRET#frag")!
        let event = RechargeNavigation.blockedEvent(url)
        XCTAssertEqual(event, "recharge.blocked https://pay.example.invalid")
        for part in ["cashier", "orderId", "99001", "SYNTH-SECRET", "frag", "443"] { XCTAssertFalse(event.contains(part), part) }
    }

    func testSchemeOnlyLinksAndOddHosts() {
        XCTAssertEqual(RechargeNavigation.blockedEvent(URL(string: "alipays://platformapi/startapp?appId=1&qrcode=SYNTH")!),
                       "recharge.blocked alipays:")
        XCTAssertEqual(RechargeNavigation.blockedEvent(URL(string: "http://Pay.Example.INVALID/x?y=1")!),
                       "recharge.blocked http://pay.example.invalid")
        XCTAssertEqual(RechargeNavigation.blockedEvent(URL(string: "weixin:pay?token=SYNTH")!), "recharge.blocked weixin:")
        XCTAssertEqual(RechargeNavigation.blockedEvent(URL(string: "https://user:pw@Pay.Example.INVALID/")!),
                       "recharge.blocked https://pay.example.invalid")
        let long = URL(string: "https://" + String(repeating: "a", count: 200) + ".example/")!
        XCTAssertLessThanOrEqual(RechargeNavigation.blockedEvent(long).count, 80, "fits one diagnostic entry")
    }

    /// The part after `scheme://` of an app link can be an identifier, so it is never logged.
    func testCustomSchemeLogsTheSchemeOnly() {
        let event = RechargeNavigation.blockedEvent(URL(string: "examplepay://SYNTH-ID-99001/pay?x=1")!)
        XCTAssertEqual(event, "recharge.blocked examplepay:")
        XCTAssertFalse(event.lowercased().contains("synth"))
    }

    /// The school login page logs its cancelled navigations, frames included, the same way.
    func testTheLoginPageLogsHostsOnly() {
        let url = URL(string: "https://tracker.example.invalid/p?uid=SYNTH-99001")!
        XCTAssertEqual(SchoolLoginNavigation.blockedEvent(url, isMainFrame: false), "login.blockedFrame https://tracker.example.invalid")
        XCTAssertEqual(SchoolLoginNavigation.blockedEvent(url, isMainFrame: true), "login.blocked https://tracker.example.invalid")
        XCTAssertEqual(SchoolLoginNavigation.blockedEvent(URL(string: "examplepay://SYNTH-ID/x")!, isMainFrame: false),
                       "login.blockedFrame examplepay:")
    }
}
