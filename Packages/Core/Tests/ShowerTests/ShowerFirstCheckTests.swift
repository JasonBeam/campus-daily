import XCTest
@testable import Core
import CoreTestSupport

/// The first 开始洗澡 reads the controller's number before anything is asked of the school, and
/// one tap may send one authorize request at most, only while nothing took the tap back
/// (`ShowerStartPermit`). Fakes only: nothing here reaches a controller or the school.
final class ShowerFirstCheckTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    let auth = ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8(0x30 + $0) }), authorizationID: "001122FF")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var identity: Data { FakeFrames.identity(machine) }

    var vault: HookedShowerVault!
    var transport: FakeShowerTransport!
    var gateway: FakeGateway!
    var hooks: RecordingHooks!

    override func setUp() { reset() }

    func reset() {
        vault = HookedShowerVault()
        transport = FakeShowerTransport()
        gateway = FakeGateway()
        hooks = RecordingHooks()
    }

    func engine() throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault, configuration: .init(bleName: "fixture-ble"),
                         hooks: hooks, now: { [t0] in t0 })
    }

    /// Nothing asked of the school, nothing written to the controller but the probe, nothing
    /// kept: 开始洗澡 can go again.
    func assertNothingIssued(_ e: ShowerEngine, _ label: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        XCTAssertEqual(gateway.authorizeFrames, [], "authorize 0: \(label)", file: file, line: line)
        XCTAssertEqual(gateway.settleFrames, [], "settle 0: \(label)", file: file, line: line)
        XCTAssertFalse(transport.writes.contains(auth.payload), "no authorization written: \(label)", file: file, line: line)
        XCTAssertTrue(transport.writes.allSatisfy { $0 == ShowerFrames.probeCommand }, "only probes: \(label)", file: file, line: line)
        XCTAssertEqual(try vault.showerState()?.phase ?? .idle, .idle, "nothing kept: \(label)", file: file, line: line)
        let state = await e.state
        XCTAssertTrue(state.canStart, "retryable: \(label)", file: file, line: line)
        XCTAssertFalse(state.authorizeSent, label, file: file, line: line)
    }

    // MARK: The permit

    func testThePermitIsConsumedOnceAndNeverAfterARevoke() {
        let p = ShowerStartPermit()
        XCTAssertTrue(p.isOpen)
        XCTAssertTrue(p.consume())
        XCTAssertFalse(p.isOpen)
        XCTAssertFalse(p.consume(), "a second consume never authorizes again")
        XCTAssertFalse(p.revoke(), "consumed first: the request may have left")

        let q = ShowerStartPermit()
        XCTAssertTrue(q.revoke())
        XCTAssertFalse(q.isOpen)
        XCTAssertFalse(q.consume(), "revoked first: nothing is sent")
        XCTAssertFalse(q.consume())
        XCTAssertTrue(q.revoke(), "revoking again: still nothing sent")
    }

    /// Revoke and consume from many threads at once: exactly one wins.
    func testRevokeAndConsumeRaceHasOneWinner() async {
        for _ in 0..<200 {
            let p = ShowerStartPermit()
            async let consumed = Task.detached { p.consume() }.value
            async let revoked = Task.detached { p.revoke() }.value
            let (c, r) = await (consumed, revoked)
            XCTAssertNotEqual(c, r, "consumed \(c), revoked-before-send \(r)")
        }
    }

    // MARK: 1. Matching number

    func testAMatchingNumberIsReadBeforeTheOneAuthorize() async throws {
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let permit = ShowerStartPermit()
        let s = try await e.start(binding, permit: permit)
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand, auth.payload], "probe, then the authorization")
        XCTAssertEqual(gateway.authorizeFrames, [identity], "one authorize, with the number just read")
        XCTAssertFalse(permit.isOpen, "consumed by the request")
        XCTAssertFalse(permit.revoke(), "too late to take back")
    }

    /// A binding marked matched still reads the number first (the marker only picks words).
    func testAMatchedBindingStillProbesFirst() async throws {
        var matched = binding
        matched.matchedAt = t0
        matched.peripheralID = "PERIPHERAL-A"
        let e = try engine()
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        _ = try await e.start(matched, permit: ShowerStartPermit())
        XCTAssertEqual(transport.writes.first, ShowerFrames.probeCommand)
        XCTAssertEqual(gateway.authorizeFrames, [identity])
    }

    // MARK: 2. Not this dorm's controller, or no number

    func testEveryPreAuthorizeFailureIssuesNothing() async throws {
        let cases: [(String, () -> Void)] = [
            ("wrong id", { self.transport.script(.frame(FakeFrames.identity("99887766"))) }),
            ("in use", { self.transport.script(.frame(FakeFrames.active)) }),
            ("malformed", { self.transport.script(.frame(Data([0x01, 0x02]))) }),
            ("probe timeout", { self.transport.script(.fail(.timedOut)) }),
            ("probe disconnect", { self.transport.script(.fail(.disconnected)) }),
            ("not found", { self.transport.scriptConnect(.failure(.notFound)) }),
            ("bluetooth off", { self.transport.scriptConnect(.failure(.bluetoothOff)) }),
            ("no permission", { self.transport.scriptConnect(.failure(.unauthorized)) }),
        ]
        for (label, script) in cases {
            reset()
            script()
            gateway.scriptAuthorize(.ok(auth))
            let e = try engine()
            let s = try await e.start(binding, permit: ShowerStartPermit())
            XCTAssertEqual(s.phase, .failed, label)
            XCTAssertEqual(s.failure?.needsReview, false, label)
            XCTAssertNotNil(FirstCheckFailure.of(s.failure), label)
            try await assertNothingIssued(e, label)
        }
    }

    func testNoPermissionIsToldApartFromBluetoothOff() async throws {
        transport.scriptConnect(.failure(.unauthorized))
        let s = try await engine().start(binding, permit: ShowerStartPermit())
        XCTAssertEqual(s.failure?.deviceError, .unauthorized)
        XCTAssertEqual(FirstCheckFailure.of(s.failure), .noPermission)
        reset()
        transport.scriptConnect(.failure(.bluetoothOff))
        let off = try await engine().start(binding, permit: ShowerStartPermit())
        XCTAssertEqual(FirstCheckFailure.of(off.failure), .off)
    }

    // MARK: 3. The remembered controller was replaced

    func testAReplacedRememberedControllerIsForgottenAndScannedOnce() async throws {
        var remembered = binding
        remembered.peripheralID = "OLD"
        try vault.saveBinding(remembered)
        transport.scriptConnect(.success("OLD"), .success("NEW"))
        transport.script(.frame(FakeFrames.identity("99887766")), .frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await engine().start(remembered, permit: ShowerStartPermit())
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(gateway.authorizeFrames.count, 1)
        XCTAssertEqual(transport.connects.count, 2, "one rescan")
        XCTAssertEqual(try vault.binding()?.peripheralID, "NEW")
    }

    // MARK: 4 / 11a. Taken back before the request

    /// Revoked while the number is read: the probe matches, then nothing is asked.
    func testARevokeDuringTheProbeStopsTheAuthorize() async throws {
        let permit = ShowerStartPermit()
        transport.onExchange = { if $0 == ShowerFrames.probeCommand { permit.revoke() } }
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let e = try engine()
        let s = try await e.start(binding, permit: permit)
        XCTAssertEqual(s.phase, .failed)
        XCTAssertEqual(s.failure?.deviceError, .interrupted)
        XCTAssertNil(FirstCheckFailure.of(s.failure), "a withdrawn start has no check line")
        try await assertNothingIssued(e, "revoked during the probe")
        XCTAssertTrue(hooks.events.contains("start.invalidated"))
    }

    /// Revoked at the last moment: after "sent" was saved, right before the request. The
    /// revoke wins, nothing leaves, and the record goes back to idle.
    func testARevokeRightBeforeTheRequestWins() async throws {
        let permit = ShowerStartPermit()
        vault.onSave = { state in
            if state?.phase == .authorizing, state?.authorizeSent == true { permit.revoke() }
        }
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let e = try engine()
        _ = try await e.start(binding, permit: permit)
        try await assertNothingIssued(e, "revoked before the request")
        let relaunched = try await engine().state
        XCTAssertEqual(relaunched.phase, .idle)
    }

    // MARK: 5 / 11b. Consumed first

    /// The request left (consumed), then the tap is taken back: the revoke says so, and the
    /// uncertain answer is kept for the check, not cleared, not asked again.
    func testARevokeAfterTheRequestLeftChangesNothing() async throws {
        let permit = ShowerStartPermit()
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.fail(.timedOut))
        let e = try engine()
        let s = try await e.start(binding, permit: permit)
        XCTAssertFalse(permit.revoke(), "consumed: may have left")
        XCTAssertEqual(s.phase, .failed)
        XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
        XCTAssertEqual(s.failure?.needsReview, true)
        XCTAssertFalse(s.canStart)
        XCTAssertNil(FirstCheckFailure.of(s.failure), "after the request: no check line, the record stays")
        XCTAssertEqual(try vault.showerState()?.failure?.reason, .authorizeUncertain, "kept")
        XCTAssertEqual(gateway.authorizeFrames.count, 1, "never asked twice")
        let again = await e.state
        XCTAssertEqual(again.failure?.reason, .authorizeUncertain)
    }

    /// 11b, the race's other side: `consume()` won and the request is out (held at the school);
    /// a `revoke()` then returns false and changes nothing. Released as uncertain, or as OK with
    /// the write timing out, the record on disk is the one the request left: kept for review or
    /// waiting on its write, never asked a second time, never settled.
    func testARevokeWhileTheRequestIsOutChangesNothing() async throws {
        for released in ["uncertain", "ok+write timeout"] {
            reset()
            let held = HeldGateway()
            let permit = ShowerStartPermit()
            if released == "uncertain" { transport.script(.frame(identity)) }
            else { transport.script(.frame(identity), .fail(.timedOut)) }
            let e = try ShowerEngine(transport: transport, gateway: held, vault: vault, configuration: .init(bleName: "fixture-ble"),
                                     hooks: hooks, now: { [t0] in t0 })
            let start = Task { [e, b = binding, permit] in try await e.start(b, permit: permit) }
            await eventually(seconds: 5) { held.authorizeCount == 1 }
            XCTAssertEqual(held.authorizeCount, 1, released)
            XCTAssertFalse(permit.revoke(), "\(released): consumed, the request is out")
            XCTAssertEqual(try vault.showerState()?.authorizeSent, true, "\(released): marked sent before it left")
            held.release(released == "uncertain" ? .failure(ServiceError.timedOut) : .success(auth))
            let s = try await start.value
            let disk = try vault.showerState()
            if released == "uncertain" {
                XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
                XCTAssertEqual(disk?.failure?.reason, .authorizeUncertain, "kept")
                XCTAssertEqual(disk?.failure?.needsReview, true)
            } else {
                XCTAssertEqual(s.phase, .writePending)
                XCTAssertEqual(disk?.phase, .writePending, "kept")
            }
            XCTAssertFalse(disk?.canStart ?? true, released)
            XCTAssertNil(FirstCheckFailure.of(s.failure), released)
            try? await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(held.authorizeCount, 1, "\(released): never asked twice")
            XCTAssertEqual(held.settleCount, 0, "\(released): nothing settled")
            let after = await e.state
            XCTAssertEqual(after.phase, s.phase, released)
        }
    }

    /// The authorization arrived but its write timed out: the record waits on its write.
    func testAWriteTimeoutAfterTheAuthorizeIsKept() async throws {
        let permit = ShowerStartPermit()
        transport.script(.frame(identity), .fail(.timedOut))
        gateway.scriptAuthorize(.ok(auth))
        let s = try await engine().start(binding, permit: permit)
        XCTAssertEqual(s.phase, .writePending)
        XCTAssertFalse(permit.revoke())
        XCTAssertEqual(try vault.showerState()?.phase, .writePending)
        XCTAssertNil(FirstCheckFailure.of(s.failure))
    }

    /// The "sent" mark can't be saved: nothing is asked.
    func testASaveFailureBeforeTheAuthorizeSendsNothing() async throws {
        vault.failWhen = { $0?.authorizeSent == true }
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.ok(auth))
        let e = try engine()
        do { _ = try await e.start(binding, permit: ShowerStartPermit()); XCTFail("storage") } catch {}
        XCTAssertEqual(gateway.authorizeFrames, [])
    }

    // MARK: 11c. Revoked before it began

    func testARevokedPermitConnectsNothing() async throws {
        for label in ["start", "startNext", "startOrNext"] {
            reset()
            if label != "start" {
                var stopped = ShowerState(phase: .running, machineID: machine, peripheralID: "PERIPHERAL-A", startedAt: t0,
                                          authorizeSent: true, authorizationID: "AABBCCDD")
                stopped.stateReviewRequired = true
                try vault.saveShowerState(stopped)
            }
            let permit = ShowerStartPermit()
            permit.revoke()
            let e = try engine()
            do {
                switch label {
                case "start": _ = try await e.start(binding, permit: permit)
                case "startNext": _ = try await e.startNext(binding, permit: permit)
                default: _ = try await e.startOrNext(binding, permit: permit)
                }
            } catch {}
            XCTAssertEqual(transport.connects.count, 0, label)
            XCTAssertEqual(transport.writes, [], label)
            XCTAssertEqual(gateway.authorizeFrames, [], label)
            XCTAssertEqual(try vault.retainedShowers(), [], label)
        }
    }

    // MARK: 7. 开始下一次洗澡 taken back

    var stopped: ShowerState {
        var s = ShowerState(phase: .running, machineID: machine, peripheralID: "PERIPHERAL-A", startedAt: t0.addingTimeInterval(-600),
                            authorizeSent: true, authorizationID: "AABBCCDD")
        s.stateReviewRequired = true
        return s
    }

    /// 7a: taken back while connecting or probing, before the old record is kept: the old one
    /// stays where it is, nothing kept aside, nothing asked, nothing settled.
    func testANextUseRevokedBeforeTheRetainChangesNothing() async throws {
        try vault.saveShowerState(stopped)
        let permit = ShowerStartPermit()
        transport.onExchange = { if $0 == ShowerFrames.probeCommand { permit.revoke() } }
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let e = try engine()
        let s = try await e.startNext(binding, permit: permit)
        XCTAssertEqual(s.persistable, stopped, "the current record is unchanged")
        XCTAssertEqual(try vault.showerState(), stopped)
        XCTAssertEqual(try vault.retainedShowers(), [], "retain 0")
        XCTAssertEqual(gateway.authorizeFrames, [])
        XCTAssertEqual(gateway.settleFrames, [])
        XCTAssertEqual(transport.writes, [ShowerFrames.probeCommand])
    }

    /// 7b: taken back after the old record was kept, before the new request: the old record is
    /// kept exactly once as it was, the new one asks nothing and ends at rest.
    func testANextUseRevokedAfterTheRetainAsksNothing() async throws {
        try vault.saveShowerState(stopped)
        let permit = ShowerStartPermit()
        vault.onRetain = { _ in permit.revoke() }
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        gateway.scriptAuthorize(.ok(auth))
        let e = try engine()
        let s = try await e.startNext(binding, permit: permit)
        XCTAssertEqual(try vault.retainedShowers(), [stopped], "kept once, as it was")
        XCTAssertEqual(gateway.authorizeFrames, [], "new authorize 0")
        XCTAssertEqual(gateway.settleFrames, [], "the old one is not settled")
        XCTAssertEqual(s.failure?.needsReview ?? false, false, "the new record ends safe")
        XCTAssertEqual(try vault.showerState()?.phase ?? .idle, .idle)
        XCTAssertFalse(transport.writes.contains(auth.payload))
    }

    // MARK: 8. Failure → reason

    func testFailureMapping() {
        func f(_ reason: ShowerFailureReason, _ device: ShowerDeviceError? = nil, review: Bool = false) -> ShowerFailure {
            ShowerFailure(reason: reason, needsReview: review, deviceError: device)
        }
        XCTAssertEqual(FirstCheckFailure.of(f(.deviceUnavailable, .notFound)), .notFound)
        XCTAssertEqual(FirstCheckFailure.of(f(.wrongDevice)), .otherMachine)
        XCTAssertEqual(FirstCheckFailure.of(f(.deviceUnavailable, .ambiguous)), .otherMachine)
        XCTAssertEqual(FirstCheckFailure.of(f(.deviceBusy)), .inUse)
        XCTAssertEqual(FirstCheckFailure.of(f(.deviceUnavailable, .bluetoothOff)), .off)
        XCTAssertEqual(FirstCheckFailure.of(f(.deviceUnavailable, .unauthorized)), .noPermission)
        for device in [ShowerDeviceError.timedOut, .disconnected, .malformedFrame, .busy] {
            XCTAssertEqual(FirstCheckFailure.of(f(.deviceUnavailable, device)), .readFailed, device.rawValue)
        }
        XCTAssertEqual(FirstCheckFailure.of(f(.deviceUnavailable)), .readFailed)
        XCTAssertNil(FirstCheckFailure.of(f(.deviceUnavailable, .interrupted)), "a cancel or a withdrawn start")
        XCTAssertNil(FirstCheckFailure.of(nil))
        // After the request: never a check line.
        for reason in [ShowerFailureReason.authorizeRefused, .authorizeUncertain, .authorizationInvalid, .closeUnconfirmed,
                       .closeBusy, .settleRefused, .settleUncertain, .settleUnconfirmed] {
            XCTAssertNil(FirstCheckFailure.of(f(reason, review: reason != .authorizeRefused)), reason.rawValue)
        }
        // Anything kept for the check is never one.
        XCTAssertNil(FirstCheckFailure.of(f(.deviceUnavailable, .notFound, review: true)))
    }

    func testFailureLinks() {
        XCTAssertEqual(FirstCheckFailure.otherMachine.link, .dorm)
        XCTAssertEqual(FirstCheckFailure.noPermission.link, .settings)
        for f in [FirstCheckFailure.notFound, .inUse, .off, .readFailed] { XCTAssertNil(f.link) }
        XCTAssertEqual(FirstCheckFailure.linkTitle(.dorm, clear: false), "改宿舍")
        XCTAssertEqual(FirstCheckFailure.linkTitle(.dorm, clear: true), "更改宿舍")
        XCTAssertEqual(FirstCheckFailure.linkTitle(.settings, clear: false), "去设置")
        XCTAssertEqual(FirstCheckFailure.linkTitle(.settings, clear: true), "前往设置")
    }

    // MARK: 10. Words

    func testCopyBothThemes() {
        XCTAssertEqual(FirstCheckFailure.inUse.text(clear: false), "附近的水控有人在用，现在核对不了是不是你宿舍的那台。等它停了再点开始。")
        XCTAssertEqual(FirstCheckFailure.inUse.text(clear: true), "附近水控正在使用，暂无法核对是否为本宿舍水控；请待其停止后重试")
        XCTAssertEqual(FirstCheckFailure.readFailed.text(clear: false), "没读到水控编号。靠近水控再点开始。")
        XCTAssertEqual(FirstCheckFailure.readFailed.text(clear: true), "未能读取水控编号；请靠近水控后重试")
        XCTAssertEqual(FirstCheckFailure.notFound.text(clear: false), "没找到水控。走到水控旁边再点开始。")
        XCTAssertEqual(FirstCheckFailure.noPermission.text(clear: true), "校日常未获得蓝牙权限；请在系统设置中允许后重试")
        for f in FirstCheckFailure.allCases {
            XCTAssertFalse(f.text(clear: true).hasSuffix("。"), "清爽 ends without a full stop: \(f)")
            XCTAssertTrue(f.text(clear: false).hasSuffix("。"), "暖橙 ends with one: \(f)")
        }
        XCTAssertEqual(FirstCheckText.explainerTitle(clear: false), "先核对你宿舍的水控")
        XCTAssertEqual(FirstCheckText.explainerTitle(clear: true), "首次洗澡前核对水控")
        XCTAssertEqual(FirstCheckText.explainerConfirm(clear: false), "好，开始")
        XCTAssertEqual(FirstCheckText.explainerLater(clear: true), "稍后")
        XCTAssertEqual(FirstCheckText.checkingButton, "正在核对水控…")
        XCTAssertEqual(FirstCheckText.checkingLine(clear: false), "这一步只看编号，不发开水指令。")
        XCTAssertEqual(FirstCheckText.checkingLine(clear: true), "此步仅读取水控编号，不发送出水指令")
        XCTAssertEqual(FirstCheckText.passed(clear: false), "找到了，是你宿舍的水控。")
        XCTAssertEqual(FirstCheckText.shortcutNeverAsked(clear: true), "首次洗澡需在校日常中点「开始洗澡」以核对水控")
        for text in [FirstCheckText.explainerBody(clear: false), FirstCheckText.explainerBody(clear: true)] {
            XCTAssertFalse(text.contains("只读"), "「只读」 is not said")
        }
    }

    // MARK: 11. The marker

    func testABindingSavedBeforeTheMarkerReadsWithout() throws {
        let old = Data(#"{"studentId":"S1","schoolId":"1","machineId":"11223344","roomId":"R","roomLabel":"1","peripheralID":"P"}"#.utf8)
        let b = try JSONDecoder().decode(ShowerBinding.self, from: old)
        XCTAssertNil(b.matchedAt)
        XCTAssertEqual(b.peripheralID, "P")
        var marked = b
        marked.matchedAt = t0
        let back = try JSONDecoder().decode(ShowerBinding.self, from: JSONEncoder().encode(marked))
        XCTAssertEqual(back.matchedAt, t0)
        XCTAssertTrue(back.sameIdentity(b), "the marker and the controller are not the identity")
    }

    // MARK: 9. The page

    func reduce(_ flow: inout ShowerPageFlow, _ event: ShowerPageEvent) -> [ShowerPageEffect] {
        let (next, effects) = ShowerPageFlow.reduce(flow, event)
        flow = next
        return effects
    }

    func testAFirstCheckStaysOnTheScreenUntilTheNumberMatched() {
        var flow = ShowerPageFlow(record: .idle)
        XCTAssertEqual(reduce(&flow, .firstCheckTapped), [.start])
        XCTAssertFalse(flow.presented, "phase A shows on the 热水洗澡 screen")
        XCTAssertTrue(flow.checking)
        let a = ShowerState(phase: .authorizing, machineID: machine)
        _ = reduce(&flow, .record(a))
        XCTAssertTrue(flow.checking)
        XCTAssertFalse(flow.presented)
        var b = a
        b.authorizeSent = true
        b.peripheralID = "P"
        _ = reduce(&flow, .record(b))
        XCTAssertFalse(flow.checking)
        XCTAssertTrue(flow.presented, "phase B: the page as today")
        XCTAssertEqual(flow.checkPassed, 1)
        _ = reduce(&flow, .record(b))
        XCTAssertEqual(flow.checkPassed, 1, "once")
    }

    /// 清爽's one 热水洗澡 page: the check is drawn on its ready face, not the connecting one.
    func testClearsPageShowsTheReadyFaceWhileChecking() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .firstCheckTapped)
        XCTAssertNil(flow.pushedPhase)
        _ = reduce(&flow, .record(ShowerState(phase: .authorizing, machineID: machine)))
        XCTAssertNil(flow.pushedPhase)
        var sent = ShowerState(phase: .authorizing, machineID: machine)
        sent.authorizeSent = true
        _ = reduce(&flow, .record(sent))
        XCTAssertEqual(flow.pushedPhase, .connecting, "after the match: the page as today")
        var plain = ShowerPageFlow(record: .idle)
        _ = reduce(&plain, .startTapped)
        XCTAssertEqual(plain.pushedPhase, .connecting, "a matched start: unchanged")
    }

    func testAFirstCheckFailureIsALineNotAFace() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .firstCheckTapped)
        _ = reduce(&flow, .record(ShowerState(phase: .authorizing, machineID: machine)))
        var failed = ShowerState(phase: .failed, machineID: machine)
        failed.failure = ShowerFailure(reason: .wrongDevice, needsReview: false)
        let effects = reduce(&flow, .record(failed))
        XCTAssertEqual(effects, [.dismissRecord])
        XCTAssertFalse(flow.presented)
        XCTAssertEqual(flow.checkFailure, .otherMachine)
        _ = reduce(&flow, .startReturned)
        XCTAssertFalse(flow.firstCheck)
        XCTAssertEqual(flow.checkFailure, .otherMachine, "stays until the next tap")
        _ = reduce(&flow, .record(.idle))
        XCTAssertEqual(flow.checkFailure, .otherMachine)
        _ = reduce(&flow, .firstCheckTapped)
        XCTAssertNil(flow.checkFailure, "cleared by the next tap")
    }

    func testAWithdrawnFirstCheckLeavesNoLine() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .firstCheckTapped)
        var failed = ShowerState(phase: .failed, machineID: machine)
        failed.failure = ShowerFailure(reason: .deviceUnavailable, needsReview: false, deviceError: .interrupted)
        XCTAssertEqual(reduce(&flow, .record(failed)), [.dismissRecord])
        XCTAssertNil(flow.checkFailure)
        XCTAssertFalse(flow.presented)
    }

    /// Taken back while the number was read (退出登录 during the probe): the engine's "sent" mark
    /// comes before the permit's last word, so it no longer brings the page up or says 找到了;
    /// the withdrawn start ends as a cleared record with no line.
    func testAWithdrawnFirstChecksSentMarkIsNotTheRequestLeaving() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .firstCheckTapped)
        _ = reduce(&flow, .record(ShowerState(phase: .authorizing, machineID: machine)))
        _ = reduce(&flow, .firstCheckWithdrawn)
        var marked = ShowerState(phase: .authorizing, machineID: machine)
        marked.authorizeSent = true
        XCTAssertEqual(reduce(&flow, .record(marked)), [])
        XCTAssertFalse(flow.presented)
        XCTAssertEqual(flow.checkPassed, 0, "no 找到了")
        XCTAssertTrue(flow.checking, "still 核对水控 on the screen")
        var refused = ShowerState(phase: .failed, machineID: machine)
        refused.failure = ShowerFailure(reason: .deviceUnavailable, needsReview: false, deviceError: .interrupted)
        XCTAssertEqual(reduce(&flow, .record(refused)), [.dismissRecord])
        XCTAssertFalse(flow.presented)
        XCTAssertNil(flow.checkFailure)
        XCTAssertFalse(flow.firstCheckWithdrawn)
    }

    /// Taken back after the permit's last word: the request had left, and what follows it is
    /// today's page (written, or kept for review).
    func testAWithdrawnFirstCheckWhoseRequestLeftIsTodaysFlow() {
        var unclear = ShowerState(phase: .failed, machineID: machine, authorizeSent: true)
        unclear.failure = ShowerFailure(reason: .authorizeUncertain, needsReview: true)
        for after in [ShowerState(phase: .writePending, machineID: machine, authorizeSent: true), unclear] {
            var flow = ShowerPageFlow(record: .idle)
            _ = reduce(&flow, .firstCheckTapped)
            _ = reduce(&flow, .firstCheckWithdrawn)
            _ = reduce(&flow, .record(after))
            XCTAssertTrue(flow.presented, "\(after.phase)")
            XCTAssertFalse(flow.firstCheck)
        }
    }

    func testAWithdrawalWithoutAFirstCheckChangesNothing() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .startTapped)
        let before = flow
        XCTAssertEqual(reduce(&flow, .firstCheckWithdrawn), [])
        XCTAssertEqual(flow, before)
    }

    /// After the request left, a first check's outcome is today's: the kept record's face.
    func testAfterTheRequestTheFirstCheckIsTodaysFlow() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .firstCheckTapped)
        var unclear = ShowerState(phase: .failed, machineID: machine, authorizeSent: true)
        unclear.failure = ShowerFailure(reason: .authorizeUncertain, needsReview: true)
        XCTAssertEqual(reduce(&flow, .record(unclear)), [])
        XCTAssertNil(flow.checkFailure)
        XCTAssertTrue(flow.presented, "the stopped face comes up")
    }

    /// A start on a matched binding keeps today's faces.
    func testAPlainStartKeepsTheConnectFailedFace() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .startTapped)
        XCTAssertTrue(flow.presented)
        XCTAssertFalse(flow.checking)
        var failed = ShowerState(phase: .failed, machineID: machine)
        failed.failure = ShowerFailure(reason: .deviceUnavailable, needsReview: false, deviceError: .notFound)
        XCTAssertEqual(reduce(&flow, .record(failed)), [])
        _ = reduce(&flow, .startReturned)
        XCTAssertEqual(flow.page?.phase, .connectFailed)
        XCTAssertNil(flow.checkFailure)
    }

    func testARefusalBeforeTheStartIsALine() {
        var flow = ShowerPageFlow(record: .idle)
        _ = reduce(&flow, .checkFailed(.noPermission))
        XCTAssertEqual(flow.checkFailure, .noPermission)
        XCTAssertFalse(flow.presented)
        _ = reduce(&flow, .checkLineCleared)
        XCTAssertNil(flow.checkFailure)
    }
}

/// A vault that tells when the record is saved or a record kept aside, and can refuse saves.
final class HookedShowerVault: ShowerVault, @unchecked Sendable {
    let store = InMemorySecureStore()
    private let lock = NSLock()
    private var _onSave: (@Sendable (ShowerState?) -> Void)?
    private var _onRetain: (@Sendable (ShowerState) -> Void)?
    private var _failWhen: (@Sendable (ShowerState?) -> Bool)?
    var onSave: (@Sendable (ShowerState?) -> Void)? { get { lock.withLock { _onSave } } set { lock.withLock { _onSave = newValue } } }
    var onRetain: (@Sendable (ShowerState) -> Void)? { get { lock.withLock { _onRetain } } set { lock.withLock { _onRetain = newValue } } }
    var failWhen: (@Sendable (ShowerState?) -> Bool)? { get { lock.withLock { _failWhen } } set { lock.withLock { _failWhen = newValue } } }
    private var inner: StoredShowerVault { StoredShowerVault(store: store) }

    func binding() throws -> ShowerBinding? { try inner.binding() }
    func saveBinding(_ binding: ShowerBinding?) throws { try inner.saveBinding(binding) }
    func showerState() throws -> ShowerState? { try inner.showerState() }
    func saveShowerState(_ state: ShowerState?) throws {
        if failWhen?(state) == true { throw StorageError(operation: "save", status: -1) }
        try inner.saveShowerState(state)
        onSave?(state)
    }
    func retainedShowers() throws -> [ShowerState] { try inner.retainedShowers() }
    func retainShower(_ state: ShowerState) throws {
        try inner.retainShower(state)
        onRetain?(state)
    }
}

/// A gateway whose authorize request is counted, then held until `release`.
final class HeldGateway: ShowerGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var _authorizes = 0
    private var _settles = 0
    private var held: CheckedContinuation<Result<ShowerAuthorization, Error>, Never>?
    private var early: Result<ShowerAuthorization, Error>?
    var authorizeCount: Int { lock.withLock { _authorizes } }
    var settleCount: Int { lock.withLock { _settles } }

    func authorize(_ binding: ShowerBinding, frame: Data) async throws -> ShowerAuthorization {
        let result = await withCheckedContinuation { (c: CheckedContinuation<Result<ShowerAuthorization, Error>, Never>) in
            let ready: Result<ShowerAuthorization, Error>? = lock.withLock {
                _authorizes += 1
                if let early { self.early = nil; return early }
                held = c
                return nil
            }
            if let ready { c.resume(returning: ready) }
        }
        return try result.get()
    }

    func settle(_ binding: ShowerBinding, frame: Data) async throws -> ShowerReceipt {
        lock.withLock { _settles += 1 }
        throw ServiceError.timedOut
    }

    func release(_ result: Result<ShowerAuthorization, Error>) {
        let c: CheckedContinuation<Result<ShowerAuthorization, Error>, Never>? = lock.withLock {
            defer { held = nil }
            if held == nil { early = result }
            return held
        }
        c?.resume(returning: result)
    }
}
