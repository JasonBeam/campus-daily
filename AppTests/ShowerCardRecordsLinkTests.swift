import XCTest
import Core
@testable import XiaoRiChang

/// 暖橙's hot-water lines send the user to 校园卡记录, where the charge shows about an hour later,
/// and the places a tap can go there carry 「看校园卡记录」 while signed in to the school.
@MainActor
final class ShowerCardRecordsLinkTests: XCTestCase {
    func testTheLinesNameTheCardRecords() {
        XCTAssertEqual(ShowerModel.recordUnreadableText, "读不到热水记录。去校园卡记录里看看这次扣了没有，扣费要 1 小时左右才出现。")
        XCTAssertEqual(ShowerPageText.unreadableClearNote,
                       "先去校园卡记录里看看这次扣了没有，扣费要 1 小时左右才出现。清除以后，校日常不会再结算这一次。")
        XCTAssertEqual(ShowerPageText.stoppedNote, "在水控上按停就算洗完了。费用看校园卡记录，扣费要 1 小时左右才出现。")
    }

    func testTheLinkSaysWhereItGoes() {
        XCTAssertEqual(ShowerPageText.cardRecordsLink, "看校园卡记录")
    }

    /// Under a refusal of the school's, not under 有人在用 (no charge to look for); never while
    /// signed out (校园卡记录 can't open then).
    func testTheRefusedFaceLinksOnlyWhenThereIsSomethingToLookUp() {
        XCTAssertTrue(ShowerPageText.refusedLinkShown(inUse:false, signedIn:true))
        XCTAssertFalse(ShowerPageText.refusedLinkShown(inUse:true, signedIn:true))
        XCTAssertFalse(ShowerPageText.refusedLinkShown(inUse:false, signedIn:false))
    }

    /// The link opens 校园卡记录 only with a school account: no account, no link.
    func testTheRecordsLinkNeedsTheSchoolAccount() {
        XCTAssertNil(ShowerCardRecords().page)
        let page = ShowerCardRecords.Page(app:[], source:RecordsDemo.list.source)
        XCTAssertNotNil(ShowerCardRecords(page:page).page)
    }
}
