import XCTest
@testable import Core
import CoreTestSupport

/// The stored card session was dead and the other process had stored a newer one: checking that
/// one is cancelled (the widget at its deadline). Nothing is known, so it is an interruption,
/// not 「网络不好」.
final class CancelledStaleSessionCheckTests: XCTestCase {
    func testACancelledCheckOfTheNewerSessionIsAnInterruption() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-badToken")
        let vault = h.vault
        let session = h.session()
        let task = Task {
            await session.refresh(inBackground: true, mayMint: {
                try? vault.saveEcyktSession(T.session(token: "NEWER-TOKEN"))
                withUnsafeCurrentTask { $0?.cancel() }
                return true
            }, owning: .unchecked)
        }
        let reading = await task.value
        XCTAssertEqual(reading.outcome, .interrupted)
        XCTAssertTrue(h.server.requests(path: "/getMyECard").isEmpty, "nothing is renewed")
    }

    /// The first check, of the session this read started from, cancelled the same way.
    func testACancelledCheckOfTheStoredSessionIsAnInterruption() async throws {
        let h = Harness()
        try h.signedIn(portal: true)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        let session = h.session()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await session.refresh(inBackground: true, owning: .unchecked)
        }
        let reading = await task.value
        XCTAssertEqual(reading.outcome, .interrupted)
        XCTAssertTrue(h.server.requests(path: "/getMyECard").isEmpty, "nothing is renewed")
    }
}
