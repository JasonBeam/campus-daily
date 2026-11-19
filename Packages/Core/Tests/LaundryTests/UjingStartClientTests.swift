import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// 立刻洗衣's two U净 calls: the pre-start read (`app/orders/{id}/detail`, read-only) and
/// `app/orders/{id}/control/start` (makes the machine move: state-changing, never retried).
final class UjingStartClientTests: XCTestCase {
    func testPaths() {
        XCTAssertEqual(UjingEndpoints.startCheck("TESTORDER0001"), "/api/v1/app/orders/TESTORDER0001/detail")
        XCTAssertEqual(UjingEndpoints.startWasher("TESTORDER0001"), "/api/v1/app/orders/TESTORDER0001/control/start")
        XCTAssertNotEqual(UjingEndpoints.startCheck("X"), UjingEndpoints.detail("X"), "not the order read the app uses today")
    }

    // MARK: pre-start read

    func testStartCheckDecodes() async throws {
        let server = StubServer()
        try server.serve("ujing/startCheck-ok", times: 1)
        let c = try await L.client(server).startCheck(L.orderID)
        XCTAssertEqual(c.order.id, L.orderID)
        XCTAssertEqual(c.order.deviceID, L.device)
        XCTAssertEqual(c.order.status.code, "20")
        XCTAssertEqual(c.order.paid, true)
        XCTAssertEqual(c.order.programID, 1)
        XCTAssertEqual(c.order.price, Money(fen: 400))
        XCTAssertEqual(c.moduleType, 7)
        XCTAssertEqual(c.online, true)
        XCTAssertFalse(c.selfCleanDue)
        XCTAssertFalse(c.dispenser)
        XCTAssertNil(c.block)
        let r = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.url.path, "/api/v1/app/orders/TESTORDER0001/detail")
        XCTAssertEqual(r.queryItem("additional"), "price")
        XCTAssertEqual(r.header("Authorization"), "Bearer " + L.token)
        XCTAssertTrue(server.unmatched.isEmpty)
    }

    /// Strings and numbers both: `"7"`, `"1"`, `"1.00"`.
    func testStartCheckMachineFields() async throws {
        let server = StubServer()
        let client = L.client(server)
        try server.serve("ujing/startCheck-unsupported", times: 1)
        var c = try await client.startCheck(L.orderID)
        XCTAssertEqual(c.moduleType, 1)
        XCTAssertEqual(c.block, .unsupported)

        try server.serve("ujing/startCheck-selfClean", times: 1)
        c = try await client.startCheck(L.orderID)
        XCTAssertEqual(c.moduleType, 7)
        XCTAssertEqual(c.online, true)
        XCTAssertTrue(c.selfCleanDue)
        XCTAssertEqual(c.block, .selfClean)

        try server.serve("ujing/startCheck-dispenser", times: 1)
        c = try await client.startCheck(L.orderID)
        XCTAssertTrue(c.dispenser)
        XCTAssertEqual(c.block, .dispenser)

        // Self-clean already done (an end time), or free: no need.
        let ok = try FixtureLoader.load("ujing/startCheck-selfClean")
        var data = try XCTUnwrap(ok.responseBodyValue?["data"]?.object)
        data["cleanSelfEndTime"] = .string("2026-10-30 11:00:00")
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        c = try await client.startCheck(L.orderID)
        XCTAssertFalse(c.selfCleanDue)
        data["cleanSelfEndTime"] = nil
        data["selfCleanPrice"] = .int(0)
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        c = try await client.startCheck(L.orderID)
        XCTAssertFalse(c.selfCleanDue)
        data["selfCleanEnable"] = .bool(true)
        data["selfCleanPrice"] = .double(0.5)
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        c = try await client.startCheck(L.orderID)
        XCTAssertTrue(c.selfCleanDue)

        // Offline, and a missing module type.
        data["selfCleanEnable"] = .int(0)
        data["online"] = .int(0)
        data["moduleType"] = nil
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        c = try await client.startCheck(L.orderID)
        XCTAssertEqual(c.online, false)
        XCTAssertNil(c.moduleType)
        XCTAssertEqual(c.block, .unsupported)
        data["moduleType"] = .string("7")
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        c = try await client.startCheck(L.orderID)
        XCTAssertEqual(c.block, .offline)

        // `wp_order: null` is no dispenser.
        data["online"] = .string("1")
        data["wp_order"] = .null
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        c = try await client.startCheck(L.orderID)
        XCTAssertFalse(c.dispenser)
        XCTAssertNil(c.block)
    }

    func testStartCheckFailuresAreReadFailures() async throws {
        let server = StubServer()
        let c = L.client(server)
        server.fail("GET", L.base + UjingEndpoints.startCheck(L.orderID), with: .timedOut, times: 1)
        await L.expectError(.timedOut) { _ = try await c.startCheck(L.orderID) }
        server.respond("GET", L.base + UjingEndpoints.startCheck(L.orderID), body: L.json(#"{"code":30004,"message":"订单不存在"}"#), times: 1)
        await L.expectError(.rejected(.ujing, code: "30004", message: "订单不存在")) { _ = try await c.startCheck(L.orderID) }
        let ok = try FixtureLoader.load("ujing/startCheck-ok")
        var data = try XCTUnwrap(ok.responseBodyValue?["data"]?.object)
        data["payPrice"] = .string("free")
        server.serve(ok.withResponseBody(.object(["code": .int(0), "data": .object(data)])), times: 1)
        await L.expectError(.malformed(.ujing, "data.payPrice")) { _ = try await c.startCheck(L.orderID) }
        let before = server.requests.count
        await L.expectError(.badRequest(.ujing)) { _ = try await c.startCheck("../x") }
        XCTAssertEqual(server.requests.count, before)
    }

    // MARK: start

    func testStartWasherSendsOnce() async throws {
        let server = StubServer()
        try server.serve("ujing/startWasher-ok", times: 1)
        try await L.client(server).startWasher(L.orderID)
        XCTAssertEqual(server.requests.count, 1)
        let r = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.url.path, "/api/v1/app/orders/TESTORDER0001/control/start")
        XCTAssertTrue(r.body.isEmpty)
        XCTAssertNil(r.queryItem("amount"), "no money in the start request")
    }

    /// State-changing: anything but a clear answer is `uncertain`, and nothing is sent twice.
    func testStartWasherOutcomes() async throws {
        let server = StubServer()
        let c = L.client(server)
        try server.serve("ujing/startWasher-refused", times: 1)
        await L.expectError(.rejected(.ujing, code: "errorMessage", message: "设备未关门，请关好门后再试")) { try await c.startWasher(L.orderID) }
        server.respond("GET", L.base + UjingEndpoints.startWasher(L.orderID), body: L.json(#"{"code":30050,"message":"设备离线"}"#), times: 1)
        await L.expectError(.rejected(.ujing, code: "30050", message: "设备离线")) { try await c.startWasher(L.orderID) }
        server.fail("GET", L.base + UjingEndpoints.startWasher(L.orderID), with: .timedOut, times: 1)
        await L.expectError(.uncertain(.ujing)) { try await c.startWasher(L.orderID) }
        server.fail("GET", L.base + UjingEndpoints.startWasher(L.orderID), with: .notConnectedToInternet, times: 1)
        await L.expectError(.uncertain(.ujing)) { try await c.startWasher(L.orderID) }
        server.respond("GET", L.base + UjingEndpoints.startWasher(L.orderID), status: 502, body: L.json("bad gateway"), times: 1)
        await L.expectError(.uncertain(.ujing)) { try await c.startWasher(L.orderID) }
        server.respond("GET", L.base + UjingEndpoints.startWasher(L.orderID), body: L.json("not json"), times: 1)
        await L.expectError(.uncertain(.ujing)) { try await c.startWasher(L.orderID) }
        XCTAssertEqual(server.requests.count, 6, "one request per call, never retried")
        // Empty `data` / no `errorMessage`: taken.
        server.respond("GET", L.base + UjingEndpoints.startWasher(L.orderID), body: L.json(#"{"code":0,"data":null}"#), times: 1)
        try await c.startWasher(L.orderID)
        let before = server.requests.count
        await L.expectError(.badRequest(.ujing)) { try await c.startWasher("../x") }
        await L.expectError(.sessionExpired(.ujing)) { try await L.client(server, token: nil).startWasher(L.orderID) }
        XCTAssertEqual(server.requests.count, before)
    }

    func testLogsNameTheStartCallsNotThePath() async throws {
        let server = StubServer()
        let log = RecordingLogSink()
        try server.serve("ujing/startCheck-ok")
        try server.serve("ujing/startWasher-ok")
        let c = L.client(server, log: log)
        _ = try await c.startCheck(L.orderID)
        try await c.startWasher(L.orderID)
        let lines = log.entries.map(\.line)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("startCheck"), lines[0])
        XCTAssertTrue(lines[1].contains("startWasher"), lines[1])
        for line in lines { XCTAssertFalse(line.contains(L.orderID), line) }
    }
}
