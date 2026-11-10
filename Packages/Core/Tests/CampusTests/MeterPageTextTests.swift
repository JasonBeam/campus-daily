import XCTest
import Core

final class MeterPageTextTests: XCTestCase {
    func testThePageSaysElectricityMeterAndOffersToChoose() {
        XCTAssertEqual(MeterPageText.title, "电表")
        XCTAssertEqual(MeterPageText.pickerPrompt, "找不到的话，自己选一下")
    }

    /// A slow school says to look again later, on this page only: elsewhere the shared words stay.
    func testASlowSchoolSaysToLookAgainLater() {
        XCTAssertEqual(MeterPageText.issue(ServiceError.timedOut.userMessage), "学校那边太慢了，等一下再找。")
        XCTAssertEqual(MeterPageText.issue(ServiceError.timedOut, otherwise: "x"), "学校那边太慢了，等一下再找。")
        XCTAssertEqual(ServiceError.timedOut.userMessage, "等了半天没回应，再试一次。")
    }

    func testOtherIssuesAreAsElsewhere() {
        XCTAssertEqual(MeterPageText.issue("没自动找到电表，去「电表」里选一下。"), "没自动找到电表，去「电表」里选一下。")
        XCTAssertEqual(MeterPageText.issue(ServiceError.offline, otherwise: "x"), ServiceError.offline.userMessage)
        XCTAssertEqual(MeterPageText.issue(CancellationError(), otherwise: "电表没读到，再试一次。"), "电表没读到，再试一次。")
    }
}
