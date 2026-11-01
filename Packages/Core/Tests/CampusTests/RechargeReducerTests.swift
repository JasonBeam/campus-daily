import XCTest
import Core

final class RechargeReducerTests: XCTestCase {
    func testHappyPathConfirmsByChangedValue() {
        var (s, fx) = RechargeReducer.reduce(.idle, .tapRecharge(.card, baseline: Money(fen: 790)))
        XCTAssertEqual(fx, [.prepareSession(.card)])
        (s, fx) = RechargeReducer.reduce(s, .sessionReady)
        XCTAssertEqual(fx, [.openWebPage(.card)])
        let pay = URL(string: "alipays://platformapi/startapp?x=1")!
        (s, fx) = RechargeReducer.reduce(s, .payLinkTapped(pay))
        XCTAssertEqual(fx, [.openExternal(pay)])
        (s, fx) = RechargeReducer.reduce(s, .payLinkTapped(URL(string: "https://evil.example/")!))
        XCTAssertEqual(fx, [])
        (s, fx) = RechargeReducer.reduce(s, .returnedFromPage)
        XCTAssertEqual(fx, [.readValue(.card, delaySeconds: 5)])
        (s, fx) = RechargeReducer.reduce(s, .valueRead(Money(fen: 790)))
        XCTAssertEqual(s, .confirming(.card, baseline: Money(fen: 790), attempt: 2))
        (s, fx) = RechargeReducer.reduce(s, .valueRead(Money(fen: 5790)))
        XCTAssertEqual(s, .finished(.card, delta: Money(fen: 5000)))
    }

    func testNoClaimWithoutChange() {
        var s = RechargeState.confirming(.electricity, baseline: Money(fen: 100), attempt: 1)
        for _ in 0..<3 { s = RechargeReducer.reduce(s, .valueRead(Money(fen: 100))).0 }
        XCTAssertEqual(s, .finished(.electricity, delta: nil))
    }

    func testExpiredSessionAsksLoginThenRetriesOnce() {
        var (s, fx) = RechargeReducer.reduce(.checkingSession(.card, baseline: nil, reloginUsed: false), .sessionFailed(.sessionExpired(.ecykt)))
        XCTAssertEqual(fx, [.showLogin])
        (s, fx) = RechargeReducer.reduce(s, .reloggedIn)
        XCTAssertEqual(fx, [.prepareSession(.card)])
        (s, fx) = RechargeReducer.reduce(s, .sessionFailed(.sessionExpired(.ecykt)))
        XCTAssertEqual(s, .failed(.card, .sessionExpired(.ecykt)))
        XCTAssertEqual(fx, [])
        XCTAssertEqual(RechargeReducer.reduce(.checkingSession(.card, baseline: nil, reloginUsed: false), .sessionFailed(.offline)).0,
                       .failed(.card, .offline))
    }
}
