import XCTest
import Core
@testable import XiaoRiChang

/// The live `ShowerModel` exposes the kept showers (`ShowerRetainedSummary`) read from its vault:
/// nothing when none are kept or the list can't be read.
@MainActor
final class ShowerModelRetainedTests: XCTestCase {
    func testTheModelReadsTheKeptShowers() throws {
        let store = ScriptedStore()
        try StoredShowerVault(store:store).retainShower(Fixture.awaitingReview)
        let (model, _) = liveShowerModel(store:store)
        XCTAssertEqual(model.retained?.count, 1)
        XCTAssertEqual(model.retained?.entries.first?.reason, .settleUnconfirmed)
    }

    func testNoneKeptOrUnreadableIsNil() throws {
        XCTAssertNil(liveShowerModel(store:ScriptedStore()).0.retained)
        let store = ScriptedStore()
        try store.write(Data("not json".utf8), for:.showerRetained)
        XCTAssertNil(liveShowerModel(store:store).0.retained)
    }
}
