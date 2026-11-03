import XCTest
import Core

/// Where the common-washer page goes once a machine is saved or switched.
final class WasherSetupExitTests: XCTestCase {

    private enum Page: Equatable { case laundry, washerSetup, card }

    /// Opened from home's unbound 洗衣 row: the page is swapped for the laundry page.
    func testFromHomeLandsOnLaundry() {
        XCTAssertEqual(WasherSetupExit.path([Page.washerSetup], setup: .washerSetup, laundry: .laundry), [.laundry])
    }

    /// Opened from the laundry page: back to it.
    func testFromLaundryGoesBack() {
        XCTAssertEqual(WasherSetupExit.path([Page.laundry, .washerSetup], setup: .washerSetup, laundry: .laundry), [.laundry])
    }

    /// Not the page on top (it went already): nothing changes.
    func testNotOnTopKeepsThePath() {
        XCTAssertEqual(WasherSetupExit.path([Page.card], setup: .washerSetup, laundry: .laundry), [.card])
        XCTAssertEqual(WasherSetupExit.path([Page](), setup: .washerSetup, laundry: .laundry), [])
    }

    /// Saving the machine already in the list again keeps one entry, so a setup step that waits
    /// for the list to grow would wait for ever: the save itself finishes the step.
    func testResavingTheSameMachineStillFinishesTheSetupStep() {
        let first = SavedWasher.saving(id: "test-device-0001", qrCode: "991-01", name: "3 号", in: [])
        XCTAssertEqual(first.count, 1)
        let again = SavedWasher.saving(id: "test-device-0001", qrCode: "991-01", name: "3 号机", in: first)
        XCTAssertEqual(again.count, first.count, "same machine: still one entry")
        XCTAssertEqual(again[0].name, "3 号机", "renamed in place")
        XCTAssertEqual(again[0].savedAt, first[0].savedAt, "keeps when it was first saved")
        XCTAssertTrue(WasherSetupExit.finishesSetupStep(savedAt: 2, lastSeen: 1))
        XCTAssertFalse(WasherSetupExit.finishesSetupStep(savedAt: 1, lastSeen: 1))
    }

    func testAnotherMachineIsAppended() {
        let list = SavedWasher.saving(id: "test-device-0001", qrCode: "991-01", name: "3 号", in: [])
        let next = SavedWasher.saving(id: "test-device-0002", qrCode: "991-02", name: "4 号", in: list)
        XCTAssertEqual(next.map(\.id), ["test-device-0001", "test-device-0002"])
    }
}
