import XCTest
@testable import Core
import CoreTestSupport

/// The automatic check while the app is in front: only over a record whose water may run and
/// that waits for nothing, or over a close whose outcome is unknown until the controller is seen
/// stopped; at most once per interval, and only the read-only `AA` probe.
final class ShowerAutoReviewTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }
    var close: Data { ShowerFrames.closeCommand(authorizationID: "001122FF")! }

    var vault: StoredShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!

    override func setUp() { reset() }

    func reset() {
        vault = StoredShowerVault(store: InMemorySecureStore())
        transport = FakeShowerTransport()
        gateway = FakeGateway()
    }

    func engine() throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault,
                         configuration: .init(bleName: "fixture-ble"), now: { [t0] in t0 })
    }

    func running() async throws -> ShowerEngine {
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await e.start(binding, permit: ShowerStartPermit())
        XCTAssertEqual(s.phase, .running)
        return e
    }

    // MARK: Which records

    func testOnlyWhileWaterMayRunAndUnreviewed() {
        for phase in ShowerPhase.allCases {
            for flags in 0..<(1 << 5) {
                let s = ShowerState(phase: phase, machineID: machine, startedAt: t0, authorizationID: "001122FF",
                                    stateReviewRequired: flags & 1 != 0, reviewing: flags & 2 != 0,
                                    authorizationNotWritten: flags & 4 != 0, holdSettle: flags & 16 != 0,
                                    waitingForRelease: flags & 8 != 0)
                let unflagged = flags & 0b1111 == 0
                let expected = (phase == .running || phase == .writePending) && unflagged
                XCTAssertEqual(ShowerAutoReview.eligible(s), expected, "\(phase) \(flags)")
            }
        }
    }

    /// A close whose outcome is unknown (answered busy, or no end data, also from a relaunch
    /// mid-close) is checked until the controller is seen stopped; no other failure ever is.
    func testEligibleOverAnUnsureCloseUntilSeenStopped() {
        for reason in [ShowerFailureReason.closeUnconfirmed, .closeBusy] {
            let s = ShowerState(phase: .failed, machineID: machine, startedAt: t0, authorizationID: "001122FF", closeSent: true,
                                failure: ShowerFailure(reason: reason, needsReview: true))
            XCTAssertTrue(ShowerAutoReview.eligible(s), reason.rawValue)
            var seen = s; seen.closeStopSeen = true
            XCTAssertFalse(ShowerAutoReview.eligible(seen), "seen stopped: \(reason.rawValue)")
            var reviewing = s; reviewing.reviewing = true
            XCTAssertFalse(ShowerAutoReview.eligible(reviewing), "under way: \(reason.rawValue)")
            var waiting = s; waiting.waitingForRelease = true
            XCTAssertFalse(ShowerAutoReview.eligible(waiting), "next use found it in use: \(reason.rawValue)")
        }
        let restored = ShowerReducer.restore(ShowerState(phase: .closing, machineID: machine, peripheralID: "P", startedAt: t0,
                                                         authorizationID: "001122FF", closingFrom: .running, closeSent: true))
        XCTAssertEqual(restored.failure?.reason, .closeUnconfirmed)
        XCTAssertTrue(ShowerAutoReview.eligible(restored), "relaunched mid-close")
        for reason in [ShowerFailureReason.settleUncertain, .settleUnconfirmed, .settleRefused, .authorizeUncertain, .authorizationInvalid] {
            var s = ShowerState(phase: .failed, machineID: machine, startedAt: t0, authorizationID: "001122FF", closeSent: true,
                                failure: ShowerFailure(reason: reason, needsReview: true))
            XCTAssertFalse(ShowerAutoReview.eligible(s), reason.rawValue)
            s.waitingForRelease = true
            XCTAssertFalse(ShowerAutoReview.eligible(s), reason.rawValue)
        }
    }

    func testThrottle() {
        XCTAssertEqual(ShowerAutoReview.interval, 30)
        XCTAssertEqual(ShowerAutoReview.tick, .seconds(5))
        XCTAssertTrue(ShowerAutoReview.due(lastAttempt: nil, now: t0))
        XCTAssertFalse(ShowerAutoReview.due(lastAttempt: t0, now: t0))
        XCTAssertFalse(ShowerAutoReview.due(lastAttempt: t0, now: t0.addingTimeInterval(29.9)))
        XCTAssertTrue(ShowerAutoReview.due(lastAttempt: t0, now: t0.addingTimeInterval(30)))
        // A clock set back does not hold the check off forever, nor make it run every tick.
        XCTAssertFalse(ShowerAutoReview.due(lastAttempt: t0, now: t0.addingTimeInterval(-5)))
        XCTAssertTrue(ShowerAutoReview.due(lastAttempt: t0, now: t0.addingTimeInterval(-31)))
    }

    // MARK: What it sends

    /// Water still running (`A5`): only `AA` went out, the link is kept as the manual check
    /// keeps it, and nothing reached the platform.
    func testAutoReviewSendsOnlyProbe() async throws {
        let e = try await running()
        let writes = transport.writes.count, disconnects = transport.disconnects
        let authorizes = gateway.authorizeFrames.count
        transport.script(.frame(FakeFrames.active))
        let s = try await e.autoReview(binding)
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(Array(transport.writes.dropFirst(writes)), [ShowerFrames.probeCommand])
        XCTAssertEqual(transport.disconnects, disconnects, "A5 keeps the connection")
        XCTAssertEqual(gateway.authorizeFrames.count, authorizes)
        XCTAssertTrue(gateway.settleFrames.isEmpty)
        XCTAssertFalse(transport.writes.contains(close))
    }

    /// Stopped on the controller: the record is over (as the manual check leaves it), the link
    /// is let go, and still only `AA` went out.
    func testAutoReviewFindingTheControllerStoppedEndsNothingByItself() async throws {
        let e = try await running()
        let writes = transport.writes.count, disconnects = transport.disconnects
        transport.script(.frame(identity))
        let s = try await e.autoReview(binding)
        XCTAssertEqual(s.phase, .running)
        XCTAssertTrue(s.stateReviewRequired)
        XCTAssertEqual(ShowerPage(s)?.phase, .stopped)
        XCTAssertEqual(Array(transport.writes.dropFirst(writes)), [ShowerFrames.probeCommand])
        XCTAssertEqual(transport.disconnects, disconnects + 1)
        XCTAssertTrue(gateway.settleFrames.isEmpty)

        // Over now: no further automatic check.
        await XCTAssertThrowsErrorAsync(try await e.autoReview(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
        XCTAssertEqual(transport.writes.count, writes + 1)
    }

    /// The engine itself refuses a record the rule leaves out, whatever the caller saw.
    func testTheEngineRefusesAnIneligibleRecord() async throws {
        let records = [
            ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF", closeSent: true,
                        failure: ShowerFailure(reason: .closeUnconfirmed, needsReview: true), closeStopSeen: true),
            ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF", closeSent: true,
                        failure: ShowerFailure(reason: .closeBusy, needsReview: true), closeStopSeen: true),
            ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF", closeSent: true,
                        failure: ShowerFailure(reason: .closeBusy, needsReview: true), waitingForRelease: true),
            ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF", closeSent: true,
                        consumption: "AB", failure: ShowerFailure(reason: .settleUncertain, needsReview: true)),
            ShowerState(phase: .writePending, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                        authorizationNotWritten: true),
            ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                        stateReviewRequired: true, waitingForRelease: true),
            ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                        stateReviewRequired: true),
        ]
        for record in records {
            reset()
            try vault.saveShowerState(record)
            let e = try engine()
            transport.script(.frame(FakeFrames.active))
            await XCTAssertThrowsErrorAsync(try await e.autoReview(binding)) {
                XCTAssertEqual($0 as? ShowerEngineError, .notAllowed, "\(record.phase) \(String(describing: record.failure?.reason))")
            }
            XCTAssertTrue(transport.writes.isEmpty)
            XCTAssertTrue(transport.connects.isEmpty)
        }
    }

    // MARK: Over a close whose outcome is unknown

    /// Water still running each time: only `AA` goes out, the record stays as it is, the link is
    /// let go, and it is checked again next time.
    func testOverAnUnsureCloseRepeatedRunningOnlyProbes() async throws {
        for label in ["busy", "noAnswer", "relaunch"] {
            reset()
            let e = try await unsureCloseEngine(label)
            let before = await e.state
            let writes = transport.writes.count, closes = transport.writes.filter { $0 == close }.count
            for round in 1...3 {
                let disconnects = transport.disconnects
                transport.script(.frame(FakeFrames.active))
                let s = try await e.autoReview(binding)
                XCTAssertEqual(s.phase, .failed, "\(label) \(round)")
                XCTAssertEqual(s.failure, before.failure, "\(label) \(round)")
                XCTAssertFalse(s.closeStopSeen, "\(label) \(round)")
                XCTAssertFalse(s.canFinish, "\(label) \(round)")
                XCTAssertEqual(transport.disconnects, disconnects + 1, "let go: \(label) \(round)")
                XCTAssertTrue(ShowerAutoReview.eligible(s), "checked again: \(label) \(round)")
            }
            XCTAssertEqual(Array(transport.writes.dropFirst(writes)), Array(repeating: ShowerFrames.probeCommand, count: 3), label)
            XCTAssertEqual(transport.writes.filter { $0 == close }.count, closes, "no close again: \(label)")
            XCTAssertTrue(gateway.settleFrames.isEmpty, label)
            XCTAssertEqual(gateway.authorizeFrames.count, label == "relaunch" ? 0 : 1, label)
        }
    }

    func unsureCloseEngine(_ label: String) async throws -> ShowerEngine {
        switch label {
        case "busy", "noAnswer":
            let e = try await running()
            transport.script(.frame(FakeFrames.active), label == "busy" ? .frame(FakeFrames.active) : .fail(.timedOut))
            let s = try await e.finish(binding)
            XCTAssertEqual(s.failure?.reason, label == "busy" ? .closeBusy : .closeUnconfirmed)
            return e
        default:
            try vault.saveShowerState(ShowerState(phase: .closing, machineID: machine, peripheralID: "PERIPHERAL-A", startedAt: t0,
                                                  authorizeSent: true, authorizationID: "001122FF", closingFrom: .running,
                                                  closeSent: true))
            let e = try engine()
            let st1 = await e.state
            XCTAssertEqual(st1.failure?.reason, .closeUnconfirmed)
            return e
        }
    }

    /// Another controller's identity, an unreadable answer, no answer or no link: nothing is
    /// learned, the record is not marked, and the next check goes ahead.
    func testOverAnUnsureCloseOnlyThisControllersIdleMarksItStopped() async throws {
        let replies: [FakeShowerTransport.Reply] = [.frame(FakeFrames.identity("99999999")), .frame(Data([0x12, 0x34])),
                                                     .fail(.timedOut), .fail(.disconnected), .hang]
        for reply in replies {
            reset()
            let e = try await unsureCloseEngine("busy")
            transport.script(reply)
            if case .hang = reply {
                let b = binding
                let task = Task { try await e.autoReview(b) }
                await eventually { [transport] in transport!.writes.last == ShowerFrames.probeCommand }
                task.cancel()
                _ = try? await task.value
            } else {
                _ = try await e.autoReview(binding)
            }
            let st2 = await e.state
            XCTAssertFalse(st2.closeStopSeen, "\(reply)")
            XCTAssertFalse(try XCTUnwrap(try vault.showerState()).closeStopSeen, "\(reply)")
            let st3 = await e.state
            XCTAssertTrue(ShowerAutoReview.eligible(st3), "\(reply)")
            let st4 = await e.state
            XCTAssertEqual(st4.phase, .failed)
        }
        reset()
        let e = try await unsureCloseEngine("busy")
        transport.scriptConnect(.failure(.notFound))
        let s = try await e.autoReview(binding)
        XCTAssertFalse(s.closeStopSeen)
        XCTAssertTrue(ShowerAutoReview.eligible(s))
    }

    /// This controller idle: marked and saved; the record stays failed with its fee to check (not
    /// settled, not done), A5 later never reopens it, and nothing checks it again, not after a
    /// relaunch either.
    func testOverAnUnsureCloseSeeingStopPersistsAndStops() async throws {
        for label in ["busy", "noAnswer", "relaunch"] {
            reset()
            let e = try await unsureCloseEngine(label)
            let failure = await e.state.failure
            transport.script(.frame(identity))
            let s = try await e.autoReview(binding)
            XCTAssertTrue(s.closeStopSeen, label)
            XCTAssertEqual(s.phase, .failed, label)
            XCTAssertEqual(s.failure, failure, label)
            XCTAssertNil(s.receipt, label)
            XCTAssertTrue(s.showerOver, label)
            XCTAssertTrue(try XCTUnwrap(try vault.showerState()).closeStopSeen, "saved: \(label)")
            XCTAssertFalse(ShowerAutoReview.eligible(s), label)
            await XCTAssertThrowsErrorAsync(try await e.autoReview(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }

            // A manual check that finds water running afterwards changes none of it.
            transport.script(.frame(FakeFrames.active))
            let again = try await e.review(binding)
            XCTAssertTrue(again.closeStopSeen, label)
            XCTAssertEqual(again.phase, .failed, label)
            XCTAssertFalse(again.canFinish, label)
            XCTAssertFalse(again.canRetrySettle, label)

            let relaunched = try engine()
            let st5 = await relaunched.state
            XCTAssertTrue(st5.closeStopSeen, label)
            await XCTAssertThrowsErrorAsync(try await relaunched.autoReview(binding)) { XCTAssertEqual($0 as? ShowerEngineError, .notAllowed) }
            XCTAssertTrue(gateway.settleFrames.isEmpty, label)
            XCTAssertEqual(transport.writes.filter { $0 == close }.count, label == "relaunch" ? 0 : 1, label)
        }
    }

    /// Only a check after an unsure close marks a stop: the next use's kept failure that a check
    /// finds idle is not marked as stopped after a close.
    func testTheMarkIsOnlyForAnUnsureClose() {
        var waiting = ShowerState(phase: .failed, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                                  consumption: "AB", failure: ShowerFailure(reason: .settleUncertain, needsReview: true),
                                  reviewing: true, waitingForRelease: true)
        var (s, _) = ShowerReducer.reduce(waiting, .probeReplied(identity))
        XCTAssertFalse(s.closeStopSeen)
        XCTAssertFalse(s.waitingForRelease)
        waiting.failure = ShowerFailure(reason: .authorizeUncertain, needsReview: true)
        (s, _) = ShowerReducer.reduce(waiting, .probeReplied(identity))
        XCTAssertFalse(s.closeStopSeen)
        // Over a running record that the controller shows stopped: its own flag, not this one.
        let running = ShowerState(phase: .running, machineID: machine, peripheralID: "P", startedAt: t0, authorizationID: "001122FF",
                                  reviewing: true)
        (s, _) = ShowerReducer.reduce(running, .probeReplied(identity))
        XCTAssertTrue(s.stateReviewRequired)
        XCTAssertFalse(s.closeStopSeen)
    }

    /// The automatic check runs nothing but the probe, letting the link go and notes.
    func testReadOnlyAllowsOnlyProbeReleaseAndNotes() {
        let allowed: [ShowerEffect] = [.probe(peripheralID: "P"), .probe(peripheralID: nil), .releaseDevice,
                                       .diagnostic(.reviewWriteNeverApplied)]
        let refused: [ShowerEffect] = [.connectAndProbe(machineID: machine, preferred: nil), .authorize(frame: identity),
                                       .writeAuthorization(auth.payload), .sendClose(close), .settle(frame: identity),
                                       .forgetPeripheral("P")]
        for e in allowed { XCTAssertTrue(ShowerEngine.readOnlyAllows(e), "\(e)") }
        for e in refused { XCTAssertFalse(ShowerEngine.readOnlyAllows(e), "\(e)") }
    }

    /// The app leaves the front while the check is connecting or waiting for the answer: the
    /// link is let go, the record is unchanged and the engine is free again.
    func testCancelDuringConnectOrExchangeDisconnectsAndFrees() async throws {
        for during in ["connect", "exchange"] {
            reset()
            let e = try await unsureCloseEngine("busy")
            let before = await e.state
            let disconnects = transport.disconnects
            if during == "connect" { transport.hangNextConnect() } else { transport.script(.hang) }
            let b = binding
            let task = Task { try await e.autoReview(b) }
            if during == "connect" {
                await eventually { [transport] in transport!.isConnecting }
            } else {
                await eventually { [transport] in transport!.writes.last == ShowerFrames.probeCommand }
            }
            task.cancel()
            _ = try? await task.value
            XCTAssertGreaterThan(transport.disconnects, disconnects, during)
            let s = await e.state
            XCTAssertEqual(s.phase, .failed, during)
            XCTAssertEqual(s.failure, before.failure, during)
            XCTAssertFalse(s.reviewing, during)
            XCTAssertFalse(s.closeStopSeen, during)
            // Free: the next check goes ahead.
            transport.script(.frame(identity))
            let next = try await e.autoReview(binding)
            XCTAssertTrue(next.closeStopSeen, during)
        }
    }

    /// A failed probe leaves the record as it was; the caller decides when to try again.
    func testAFailedProbeChangesNothing() async throws {
        let e = try await running()
        transport.scriptConnect(.failure(.notFound))
        let s = try await e.autoReview(binding)
        XCTAssertEqual(s.phase, .running)
        XCTAssertFalse(s.stateReviewRequired)
        XCTAssertEqual(s.notice, .device(.notFound))
        XCTAssertTrue(gateway.settleFrames.isEmpty)
    }
}

func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line,
                                  _ handler: (Error) -> Void = { _ in }) async {
    do {
        _ = try await expression()
        XCTFail("no error thrown", file: file, line: line)
    } catch {
        handler(error)
    }
}
