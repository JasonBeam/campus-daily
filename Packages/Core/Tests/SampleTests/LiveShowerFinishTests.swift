import XCTest
import Core
import CoreTestSupport

/// The end of a real shower from the Live Activity or Siri leaves the sample first.
@MainActor
final class LiveShowerFinishTests: XCTestCase {
    /// The Live Activity's button or Siri's 结束并结算 while the sample is shown: the sample is
    /// left before the live session is ended, once; afterwards the live app stays up, not the
    /// login step or the sample.
    func testEndingTheRealShowerFromTheSampleLeavesItFirst() async throws {
        let sample = SampleMode.overIdleShower()
        sample.enter()
        var ends = 0
        try await LiveShowerFinish.run(sample: sample) {
            ends += 1
            XCTAssertFalse(sample.isActive, "the sample is still shown when the live session ends")
        }
        XCTAssertEqual(ends, 1)
        XCTAssertFalse(sample.isActive)
        XCTAssertFalse(sample.takeLogin(), "after the end the live app stays up, not the login step")
        XCTAssertNil(sample.takePendingLink())
    }

    /// Outside the sample the end just runs.
    func testEndingOutsideTheSampleJustEnds() async throws {
        let sample = SampleMode.overIdleShower()
        var ends = 0
        try await LiveShowerFinish.run(sample: sample) { ends += 1 }
        XCTAssertEqual(ends, 1)
        XCTAssertFalse(sample.isActive)
    }
}
