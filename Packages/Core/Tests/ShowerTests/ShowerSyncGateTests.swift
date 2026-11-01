import XCTest
@testable import Core

final class ShowerSyncGateTests: XCTestCase {
    /// Relaunched mid-settlement: the record read at launch and the engine's first report are
    /// the same, and the lock screen and the reminder must still follow it.
    func testTheFirstReportAlwaysSyncs() {
        let restored = ShowerState(phase: .failed, failure: ShowerFailure(reason: .settleUncertain, needsReview: true))
        var gate = ShowerSyncGate()
        XCTAssertTrue(gate.shouldSync(restored, after: restored))
        XCTAssertFalse(gate.shouldSync(restored, after: restored), "after that, only changes")
        XCTAssertTrue(gate.shouldSync(.idle, after: restored))
    }

    func testANewEngineSyncsItsFirstReportAgain() {
        var gate = ShowerSyncGate()
        XCTAssertTrue(gate.shouldSync(.idle, after: .idle))
        gate.reset()
        XCTAssertTrue(gate.shouldSync(.idle, after: .idle))
    }
}
