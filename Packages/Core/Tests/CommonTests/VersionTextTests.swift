import XCTest
import Core

/// Settings › 版本: TestFlight and builds from Xcode say Beta, App Store builds don't.
final class VersionTextTests: XCTestCase {
    func testBetaAndStoreText() {
        XCTAssertEqual(VersionText.text(version: "0.8.0", build: "48", isBeta: true), "0.8.0 Beta（48）")
        XCTAssertEqual(VersionText.text(version: "0.8.0", build: "48", isBeta: false), "0.8.0（48）")
    }

    func testMissingValuesShowADash() {
        XCTAssertEqual(VersionText.text(version: nil, build: nil, isBeta: false), "—（—）")
    }

    /// TestFlight installs carry a sandbox receipt; builds from Xcode carry none; the App Store's
    /// is plain `receipt`.
    func testWhichBuildsAreBeta() {
        XCTAssertTrue(VersionText.isBeta(receiptName: "sandboxReceipt", receiptExists: true))
        XCTAssertTrue(VersionText.isBeta(receiptName: "receipt", receiptExists: false), "no receipt: a development build")
        XCTAssertTrue(VersionText.isBeta(receiptName: nil, receiptExists: false))
        XCTAssertFalse(VersionText.isBeta(receiptName: "receipt", receiptExists: true))
    }
}
