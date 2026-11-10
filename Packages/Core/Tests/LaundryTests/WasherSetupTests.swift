import XCTest
import Core

/// The common-washer page: which QR code a photo gives, and the text for each refusal.
final class WasherSetupTests: XCTestCase {
    func testOneCodeIsUsed() {
        XCTAssertEqual(WasherPhotoCodes(payloads: ["991-01"]), .one("991-01"))
        XCTAssertEqual(WasherPhotoCodes(payloads: ["991-01", "991-01", nil]), .one("991-01"), "the same code twice is one machine")
    }

    /// No code at all is its own case, not "several codes".
    func testNoCodeIsNotSeveral() {
        XCTAssertEqual(WasherPhotoCodes(payloads: []), .none)
        XCTAssertEqual(WasherPhotoCodes(payloads: [nil]), .none, "a code that can't be read counts as none")
        XCTAssertEqual(WasherPhotoCodes(payloads: ["991-01", "991-02"]), .several)
        XCTAssertNotEqual(WasherPhotoCodes.none.message, WasherPhotoCodes.several.message)
        XCTAssertEqual(WasherPhotoCodes.several.message, "照片里有好几个码，选一张只拍了一台的。")
        XCTAssertNil(WasherPhotoCodes.one("991-01").message)
    }

    func testOpenOrderComesBeforeBusy() {
        XCTAssertEqual(WasherSetupRefusal.check(orderOpen: true, busy: true), .orderOpen)
        XCTAssertEqual(WasherSetupRefusal.check(orderOpen: false, busy: true), .busy)
        XCTAssertNil(WasherSetupRefusal.check(orderOpen: false, busy: false))
    }

    func testMachineNameRules() {
        XCTAssertEqual(try WasherSetupRefusal.machineName("  991 号  ").get(), "991 号")
        XCTAssertEqual(try WasherSetupRefusal.machineName(String(repeating: "洗", count: 40)).get().count, 40)
        XCTAssertThrowsError(try WasherSetupRefusal.machineName(String(repeating: "洗", count: 41)).get())
        XCTAssertThrowsError(try WasherSetupRefusal.machineName("   ").get())
        XCTAssertThrowsError(try WasherSetupRefusal.machineName("991\n01").get())
    }

    /// Only a bad name says the name is too long; being busy or the machine being gone says so.
    func testEachRefusalHasItsOwnText() {
        let all: [WasherSetupRefusal] = [.orderOpen, .busy, .notSaved, .nothingToSave, .badName]
        XCTAssertEqual(Set(all.map(\.message)).count, all.count)
        XCTAssertEqual(WasherSetupRefusal.badName.message, "机器名称最多 40 个字。")
        XCTAssertEqual(WasherSetupRefusal.orderOpen.message, "先核对已有洗衣订单。")
        XCTAssertFalse(WasherSetupRefusal.busy.message.contains("40"))
        XCTAssertFalse(WasherSetupRefusal.notSaved.message.contains("40"))
    }
}
