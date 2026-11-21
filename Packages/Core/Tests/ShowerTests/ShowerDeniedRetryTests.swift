//
//  ShowerDeniedRetryTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import XCTest
@testable import Core
import CoreTestSupport

/// The refused face tries again in place only when the record says nothing was issued
/// (`ShowerState.canStart`): a known refusal before the platform acted, or a controller found in
/// use before the authorize. An answer that may have issued something (4060, a code nobody knows,
/// a timeout, an authorization that can't be used) stays on the stopped face with no retry.
final class ShowerDeniedRetryTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }

    func reduce(_ flow: inout ShowerPageFlow, _ event: ShowerPageEvent) -> [ShowerPageEffect] {
        let (next, effects) = ShowerPageFlow.reduce(flow, event)
        flow = next
        return effects
    }

    /// The record after the platform answered the authorize with `error`.
    func answered(_ error: ServiceError) -> ShowerState {
        let sent = ShowerState(phase: .authorizing, machineID: machine, peripheralID: "P", authorizeSent: true)
        return ShowerReducer.reduce(sent, .authorizeFailed(error)).0
    }

    func testRetryFromDeniedStartsAgainWhenNothingWasIssued() {
        let busy = ShowerReducer.reduce(ShowerState(phase: .authorizing, machineID: machine),
                                        .connected(peripheralID: "P", probe: FakeFrames.active)).0
        for record in [answered(.badRequest(.lxt6)), answered(.sessionExpired(.lxt6)), busy] {
            XCTAssertTrue(record.canStart)
            var flow = ShowerPageFlow(record: record, presented: true)
            XCTAssertEqual(flow.page?.phase, .denied, "\(String(describing: record.failure))")
            XCTAssertTrue(flow.mayRetry)
            XCTAssertEqual(reduce(&flow, .retryTapped), [.start])
            XCTAssertTrue(flow.starting)
            XCTAssertEqual(flow.page?.phase, .connecting)
            XCTAssertFalse(flow.mayRetry)
            XCTAssertEqual(reduce(&flow, .retryTapped), [], "a quick second tap starts nothing more")
            _ = reduce(&flow, .startReturned)
        }
    }

    func testNoRetryOverANeedsReviewFailure() {
        let unclear: [ServiceError] = [.officialUnfinishedOrder, .rejected(.lxt6, code: "9999", message: "未知"),
                                       .timedOut, .offline, .uncertain(.lxt6)]
        var records = unclear.map(answered)
        let sent = ShowerState(phase: .authorizing, machineID: machine, peripheralID: "P", authorizeSent: true)
        let bad = ShowerAuthorization(machineID: "99999999", payload: auth.payload, authorizationID: "001122FF")
        records.append(ShowerReducer.reduce(sent, .authorized(bad, at: t0)).0)
        for record in records {
            XCTAssertEqual(record.failure?.needsReview, true, "\(String(describing: record.failure))")
            XCTAssertFalse(record.canStart)
            var flow = ShowerPageFlow(record: record, presented: true)
            XCTAssertEqual(flow.page?.phase, .stopped, "\(String(describing: record.failure))")
            XCTAssertFalse(flow.mayRetry)
            XCTAssertEqual(reduce(&flow, .retryTapped), [], "\(String(describing: record.failure))")
            XCTAssertFalse(flow.starting)
        }
    }

    func testNoRetryAfter4060() {
        let record = answered(.officialUnfinishedOrder)
        XCTAssertEqual(record.failure?.reason, .authorizeUncertain)
        var flow = ShowerPageFlow(record: record, presented: true)
        XCTAssertEqual(flow.page?.phase, .stopped, "4060 stays on the stopped face")
        XCTAssertEqual(reduce(&flow, .retryTapped), [])
        XCTAssertEqual(reduce(&flow, .startTapped), [])
    }

    /// The retry through the engine: one new authorize per tap that the record allowed, and none
    /// over a record that waits for a check.
    func testTheRetryReachesTheEngineOnlyWhenTheRecordAllowsIt() async throws {
        let transport = FakeShowerTransport(), gateway = FakeGateway()
        let vault = StoredShowerVault(store: InMemorySecureStore())
        let e = try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                                 configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.fail(.badRequest(.lxt6)))
        let refused = try await e.start(binding, permit: ShowerStartPermit())
        var flow = ShowerPageFlow(record: refused, presented: true)
        XCTAssertEqual(flow.page?.phase, .denied)
        XCTAssertEqual(reduce(&flow, .retryTapped), [.start])
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let running = try await e.start(binding, permit: ShowerStartPermit())
        _ = reduce(&flow, .record(running))
        _ = reduce(&flow, .startReturned)
        XCTAssertEqual(flow.page?.phase, .running)
        XCTAssertEqual(gateway.authorizeFrames.count, 2)

        // A 4060 waits for its check: no retry, and the engine would refuse one anyway.
        let other = try ShowerEngine(transport: transport, gateway: gateway, vault: StoredShowerVault(store: InMemorySecureStore()),
                                     configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.fail(.officialUnfinishedOrder))
        let unfinished = try await other.start(binding, permit: ShowerStartPermit())
        var stopped = ShowerPageFlow(record: unfinished, presented: true)
        XCTAssertEqual(reduce(&stopped, .retryTapped), [])
        await XCTAssertThrowsErrorAsync(try await other.start(binding, permit: ShowerStartPermit())) { XCTAssertEqual($0 as? ShowerEngineError, .blocked) }
        XCTAssertEqual(gateway.authorizeFrames.count, 3)
    }

    /// Words of the refused face's two buttons.
    func testDeniedFaceButton() {
        XCTAssertEqual(ClearShowerText.deniedRetry, "开始洗澡")
        XCTAssertEqual(ClearShowerText.deniedClose, "好")
    }
}
