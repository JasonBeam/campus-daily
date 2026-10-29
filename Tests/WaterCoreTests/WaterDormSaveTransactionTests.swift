import XCTest
@testable import WaterCore

@MainActor final class WaterDormSaveTransactionTests: XCTestCase {
    enum Failure:Error {case campus, rollback, water}
    func testFirstUseClearsNewWaterConfigIfCampusSaveFails() {
        var savedWater: String? = nil
        XCTAssertThrowsError(try WaterDormSaveTransaction.perform(
            saveWater:{savedWater="new"}, saveCampus:{throw Failure.campus}, rollbackWater:{savedWater=nil}))
        XCTAssertNil(savedWater)
    }
    func testExistingWaterConfigIsRestoredIfCampusSaveFails() {
        var savedWater: String? = "previous"
        let old=savedWater
        XCTAssertThrowsError(try WaterDormSaveTransaction.perform(
            saveWater:{savedWater="new"}, saveCampus:{throw Failure.campus}, rollbackWater:{savedWater=old}))
        XCTAssertEqual(savedWater,"previous")
    }
    func testRollbackFailureRemainsVisibleAndWaterFailureSkipsCampusSave() {
        XCTAssertThrowsError(try WaterDormSaveTransaction.perform(
            saveWater:{}, saveCampus:{throw Failure.campus}, rollbackWater:{throw Failure.rollback})) { error in
            guard case Failure.rollback = error else {return XCTFail("Rollback failure was hidden")}
        }
        var campusCalled=false
        XCTAssertThrowsError(try WaterDormSaveTransaction.perform(
            saveWater:{throw Failure.water}, saveCampus:{campusCalled=true}, rollbackWater:{XCTFail("No saved water to roll back")}))
        XCTAssertFalse(campusCalled)
    }
}
