import XCTest
@testable import Core
import CoreTestSupport

/// The test stub itself: a request from a test that already ended (a task left running past its
/// end) never lands in a later test's server.
final class StubRoutingTests: XCTestCase {
    func testARequestForAServerThatIsGoneFailsAndReachesNoOtherServer() async throws {
        var finished: StubServer? = StubServer()
        let client = try XCTUnwrap(finished).makeClient()
        finished = nil
        let current = StubServer()
        try current.serve("ecykt/getSysBindCustInfo-ok")
        let url = try XCTUnwrap(URL(string: "https://ecykt.gdbtu.edu.cn/ykt-mini/api/customer/getSysBindCustInfo"))
        do {
            _ = try await client.send(HTTPRequest.postJSON(service: .ecykt, url: url, json: [:]))
            XCTFail("answered by another test's server")
        } catch {}
        XCTAssertTrue(current.requests.isEmpty)
        XCTAssertTrue(current.unmatched.isEmpty)
    }

    func testARequestIsRoutedToItsOwnServer() async throws {
        let first = StubServer()
        let client = first.makeClient()
        let second = StubServer()
        try first.serve("ecykt/getSysBindCustInfo-ok")
        let url = try XCTUnwrap(URL(string: "https://ecykt.gdbtu.edu.cn/ykt-mini/api/customer/getSysBindCustInfo"))
        let response = try await client.send(HTTPRequest.postJSON(service: .ecykt, url: url, json: [:]))
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(first.requests.count, 1)
        XCTAssertTrue(second.requests.isEmpty)
    }
}
