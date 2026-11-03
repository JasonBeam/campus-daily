import XCTest
import Core

private final class MemoryPreferences: PreferenceStorage {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// The common-washer page once signed in to U净: the guide card, the 「U净 账号」 section,
/// 退出 U净 and an expired login.
final class UjingAccountTests: XCTestCase {
    let mobileID = "00000000-0000-4000-8000-000000000001"
    let signedIn = UjingAccount(id: "acct-1", userId: "user-1", token: "test.synthetic-ujing-token")

    // MARK: Guide card

    func testGuideCard() {
        XCTAssertEqual(WasherSetupGuide.card(signedIn: false, hasSavedMachine: false), .signIn)
        XCTAssertEqual(WasherSetupGuide.card(signedIn: false, hasSavedMachine: true), .signIn, "signed out: the first step stays")
        XCTAssertEqual(WasherSetupGuide.card(signedIn: true, hasSavedMachine: false), .scan)
        XCTAssertNil(WasherSetupGuide.card(signedIn: true, hasSavedMachine: true), "signed in with a machine saved: no card")
    }

    // MARK: 「U净 账号」

    func testPhoneIsMaskedInTheMiddle() {
        XCTAssertEqual(UjingAccountText.maskedPhone("10012345678"), "100****5678")
        XCTAssertEqual(UjingAccountText.maskedPhone("13800000000"), "138****0000")
    }

    /// Anything but an 11-digit number is never shown in full.
    func testOddPhoneIsNotShownInFull() {
        XCTAssertEqual(UjingAccountText.maskedPhone("1234567"), "*******")
        XCTAssertEqual(UjingAccountText.maskedPhone(""), "*")
    }

    /// The login keeps the number it was made with; logins from before have none.
    func testAccountItemKeepsThePhoneAndOldItemsDecode() throws {
        let item = UjingAccountItem(mobileID: mobileID, account: signedIn, mobile: "10012345678")
        let decoded = try JSONDecoder().decode(UjingAccountItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.mobile, "10012345678")
        XCTAssertFalse(item.description.contains("5678"), "the number never goes into a description")
        let old = Data(#"{"mobileID":"00000000-0000-4000-8000-000000000001"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(UjingAccountItem.self, from: old).mobile)
    }

    // MARK: 退出 U净

    /// 退出 U净 clears the login and its number only: the install's mobile id, the saved machines
    /// and the selected machine stay, so signing in again finds them.
    func testSignOutClearsTheLoginAndKeepsTheMachines() throws {
        let vault = StoredLaundryVault(store: InMemorySecureStore())
        try vault.saveAccountItem(UjingAccountItem(mobileID: mobileID, account: signedIn, mobile: "10012345678"))
        let preferences = MemoryPreferences()
        preferences.values[PreferenceKey.laundryMachines] = Data([1, 2, 3])
        preferences.values[PreferenceKey.laundrySelected] = "test-device-0001"
        preferences.values[PreferenceKey.schoolLaundry] = true

        _ = try UjingSignOut.perform(vault: vault, preferences: preferences, checkout: nil)

        let item = try XCTUnwrap(try vault.accountItem())
        XCTAssertNil(item.account)
        XCTAssertNil(item.mobile)
        XCTAssertEqual(item.mobileID, mobileID, "the install id stays")
        XCTAssertEqual(preferences.values[PreferenceKey.laundryMachines] as? Data, Data([1, 2, 3]), "saved machines kept")
        XCTAssertEqual(preferences.values[PreferenceKey.laundrySelected] as? String, "test-device-0001", "selected machine kept")
        XCTAssertEqual(preferences.values[PreferenceKey.schoolLaundry] as? Bool, true)
    }

    /// The finished order's outcome and the last-order note belong to the account that goes.
    func testSignOutForgetsTheFinishedOrder() throws {
        let vault = StoredLaundryVault(store: InMemorySecureStore())
        try vault.saveAccountItem(UjingAccountItem(mobileID: mobileID, account: signedIn))
        let finished = LaundryCheckout(lastOutcome: LaundryOutcome(orderID: "991-01", status: LaundryOrderStatus("50"), at: Date(timeIntervalSince1970: 0)))
        try vault.saveCheckout(finished)
        let preferences = MemoryPreferences()
        preferences.values[PreferenceKey.laundryLastOrder] = Data([9])
        preferences.values[PreferenceKey.laundryMachines] = Data([1])

        let outcome = try UjingSignOut.perform(vault: vault, preferences: preferences, checkout: finished)

        XCTAssertTrue(outcome.forgotLastOrder)
        XCTAssertTrue(outcome.clearedCheckout)
        XCTAssertNil(try vault.checkout())
        XCTAssertNil(preferences.values[PreferenceKey.laundryLastOrder])
        XCTAssertEqual(preferences.values[PreferenceKey.laundryMachines] as? Data, Data([1]))
    }

    /// While an order is unfinished (or a step runs) the button is greyed; only the open order
    /// says why, since waiting a moment is enough for a running step.
    func testSignOutLockedWhileAnOrderIsUnfinished() {
        XCTAssertNil(UjingSignOut.refusal(orderOpen: false, busy: false))
        XCTAssertEqual(UjingSignOut.refusal(orderOpen: true, busy: false), .orderOpen)
        XCTAssertEqual(UjingSignOut.refusal(orderOpen: true, busy: true), .orderOpen)
        XCTAssertEqual(UjingSignOut.refusal(orderOpen: false, busy: true), .busy)
        XCTAssertEqual(UjingSignOut.footer(UjingSignOut.refusal(orderOpen: true, busy: false)), "还有一笔洗衣订单没处理完，处理完才能退出。")
        XCTAssertNil(UjingSignOut.footer(.busy))
        XCTAssertNil(UjingSignOut.footer(nil))
    }

    /// Refused: nothing is written.
    func testRefusedSignOutChangesNothing() throws {
        let vault = StoredLaundryVault(store: InMemorySecureStore())
        let item = UjingAccountItem(mobileID: mobileID, account: signedIn, mobile: "10012345678")
        try vault.saveAccountItem(item)
        let open = LaundryCheckout(phase: .verifying, orderID: "991-02", accountID: "acct-1")
        XCTAssertThrowsError(try UjingSignOut.perform(vault: vault, preferences: MemoryPreferences(), checkout: open)) {
            XCTAssertEqual($0 as? UjingSignOut.Refusal, .orderOpen)
        }
        XCTAssertEqual(try vault.accountItem(), item)
    }

    // MARK: Expired login

    /// A U净 call refused for an expired login, from a machine read or an order step, offers
    /// 重新登录 U净 with one sentence; other failures don't.
    func testExpiredLoginIsRecognised() {
        XCTAssertTrue(UjingAccountText.isExpired(ServiceError.sessionExpired(.ujing)))
        XCTAssertFalse(UjingAccountText.isExpired(ServiceError.offline))
        XCTAssertFalse(UjingAccountText.isExpired(LaundryEngineError.busy))
        XCTAssertEqual(UjingAccountText.expired, "U净 登录过期了。")
        XCTAssertEqual(UjingAccountText.relogin, "重新登录 U净")
    }

    func testSectionCopy() {
        XCTAssertEqual(UjingAccountText.title, "U净 账号")
        XCTAssertEqual(UjingAccountText.phone, "手机号")
        XCTAssertEqual(UjingAccountText.signOut, "退出 U净")
        XCTAssertEqual(UjingAccountText.confirmTitle, "退出 U净？")
        XCTAssertEqual(UjingAccountText.confirmMessage, "退出以后，要重新登录 U净 才能下单。")
        XCTAssertEqual(UjingAccountText.confirm, "退出")
        XCTAssertEqual(UjingAccountText.cancel, "取消")
    }
}
