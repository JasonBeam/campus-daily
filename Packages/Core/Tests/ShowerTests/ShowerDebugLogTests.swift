import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// The TestFlight log over whole showers: every step is there as types, lengths, codes and
/// salted tags, and no id, credential, frame or server sentence is.
final class ShowerDebugLogTests: XCTestCase {
    let machine = "11223344"
    /// Every value here is fake, and every one of them must stay out of the log.
    let binding = ShowerBinding(studentId: "S20991234", schoolId: "20021", machineId: "11223344", roomId: "R0991", roomLabel: "测试楼 991")
    let base = "https://isv.lxt6.cn/"
    let authorizeOK = #"{"code":0,"data":{"machineid":"11223344","studentId":"a1b2c3d4","systemData":"000102030405060708090a0b0c0d0e"}}"#
    /// The next shower's authorization: another id and payload.
    let authorizeNextOK = #"{"code":0,"data":{"machineid":"11223344","studentId":"e5f6a7b8","systemData":"101112131415161718191a1b1c1d1e"}}"#
    let settleOK = #"{"code":0,"data":{"pay":163}}"#
    var identity: Data { FakeFrames.identity(machine) }
    var consumption: Data { FakeFrames.identity(machine, tail: 9) }

    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_332_800))
    let utc = TimeZone(identifier: "UTC")!
    var folder: URL!
    var transport: FakeShowerTransport!
    var vault: StoredShowerVault!

    override func setUp() {
        folder = DebugLogTesting.temporaryDirectory()
        transport = FakeShowerTransport()
        vault = StoredShowerVault(store: InMemorySecureStore())
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    var secrets: [String] {
        [binding.studentId, binding.roomId, binding.roomLabel, "测试楼", machine, "a1b2c3d4", "000102030405060708090a0b0c0d0e",
         "e5f6a7b8", "101112131415161718191a1b1c1d1e",
         HexCoding.upper(consumption), HexCoding.upper(identity), "ACF4E79681", Golden.secret, "fixture-secret", Golden.sid,
         "fixture-sid", "PERIPHERAL-A", "fixture-ble", "20021"]
    }

    func client(_ server: StubServer, log: any DebugLogSink) -> LxtClient {
        LxtClient(http: server.makeClient(allowedHosts: AllowedHosts.hotWater, log: DebugHTTPLogSink(log, next: RecordingLogSink())),
                  profile: Golden.profile, random: { $0 == LxtSigning.userMsgAlphabet ? "ABC123" : "A1B2C3" })
    }

    func engine(_ gateway: ShowerGateway, log: any DebugLogSink) throws -> ShowerEngine {
        try ShowerEngine(transport: transport, gateway: gateway, vault: vault, configuration: .init(bleName: "fixture-ble"),
                         hooks: DebugLogShowerHooks(log), now: clock.function)
    }

    /// 开始 → authorize → write → 结束并结算 on a controller stopped with its own button (nothing
    /// closed or settled, the shower is over) → 开始下一次洗澡 on the idle controller (the record
    /// kept and read back, one new authorization) → 结束并结算 → close → settled → dismiss.
    func fullShower(_ log: any DebugLogSink) async throws {
        let server = StubServer()
        server.respond("POST", base + LxtEndpoints.authorize, body: Data(authorizeOK.utf8), times: 1)
        server.respond("POST", base + LxtEndpoints.authorize, body: Data(authorizeNextOK.utf8), times: 1)
        server.respond("POST", base + LxtEndpoints.settle, body: Data(settleOK.utf8), times: 1)
        try vault.saveBinding(binding)
        let e = try engine(client(server, log: log), log: log)
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        let running = try await e.start(binding)
        XCTAssertEqual(running.phase, .running)
        clock.advance(600)
        // Stopped on the controller: it answers idle with this machine's identity.
        transport.script(.frame(identity))
        let stopped = try await e.finish(binding)
        XCTAssertTrue(stopped.showerOver)
        XCTAssertTrue(stopped.canStartNext)
        clock.advance(60)
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        let next = try await e.startNext(binding)
        XCTAssertEqual(next.phase, .running)
        XCTAssertEqual(try vault.retainedShowers().count, 1, "the stopped shower kept")
        clock.advance(600)
        transport.script(.frame(FakeFrames.active), .frame(consumption))
        let done = try await e.finish(binding)
        XCTAssertEqual(done.phase, .done)
        XCTAssertEqual(done.receipt?.amount, Money(fen: 163))
        _ = try await e.dismiss()
        XCTAssertTrue(server.unmatched.isEmpty)
    }

    /// The lines without their time, in order; an expected line ending in `…` matches as a prefix.
    func assertInOrder(_ lines: [String], _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let bodies = lines.map { String($0.dropFirst(15)) }
        var i = 0
        for want in expected {
            let prefix = want.hasSuffix("…") ? String(want.dropLast()) : nil
            while i < bodies.count, !(prefix.map { bodies[i].hasPrefix($0) } ?? (bodies[i] == want)) { i += 1 }
            guard i < bodies.count else {
                return XCTFail("missing or out of order: \(want)\n" + bodies.joined(separator: "\n"), file: file, line: line)
            }
            i += 1
        }
    }

    func testAFullShowerLeavesEveryStepAndNoValue() async throws {
        let log = FileDebugLog(directory: FileDebugLog.directory(in: folder), now: clock.function, timeZone: utc)
        try await fullShower(log)
        let lines = log.lines()
        let m = log.tag(.machine(machine))
        assertInOrder(lines, [
            "shower.restore saved=none restored=idle",
            "shower.action start machine=\(m)",
            "shower.phase from=idle to=authorizing",
            "ble.connect result=ok target=scanned",
            "ble.probe type=55 len=20 verdict=idleSelf",
            "lxt.authorize sent",
            "http lxt6 POST host=lxt6 name=authorize status=200 ms=…",
            "lxt.authorize ok dataLength=15 idHex8=yes",
            "shower.phase from=authorizing to=writePending",
            "ble.authWrite out=15 replied type=AA len=9 ack=yes",
            "shower.phase from=writePending to=running",
            "shower.action finish",
            "shower.phase from=running to=closing",
            "ble.connect result=ok target=required samePeripheral=yes",
            "ble.probe type=55 len=20 verdict=idleSelf",
            "shower.phase from=closing to=running stateReviewRequired showerOver notice=notActive",
            "shower.action startNext machine=\(m)",
            "ble.connect result=ok target=preferred samePeripheral=yes",
            "ble.probe type=55 len=20 verdict=idleSelf",
            "shower.note nextUse.recordKept.readBackOK",
            "shower.phase from=running to=authorizing",
            "lxt.authorize sent",
            "http lxt6 POST host=lxt6 name=authorize status=200 ms=…",
            "lxt.authorize ok dataLength=15 idHex8=yes",
            "shower.phase from=authorizing to=writePending",
            "ble.authWrite out=15 replied type=AA len=9 ack=yes",
            "shower.phase from=writePending to=running",
            "shower.action finish",
            "shower.phase from=running to=closing",
            "ble.probe type=A5 len=1 verdict=active",
            "ble.close replied type=55 len=20 consumption=yes",
            "shower.phase from=closing to=settling",
            "lxt.settle sent",
            "http lxt6 POST host=lxt6 name=settle status=200 ms=…",
            "lxt.settle ok fen=163",
            "shower.phase from=settling to=done",
            "shower.action dismiss",
            "shower.phase from=done to=idle",
        ])
        let nextAt = try XCTUnwrap(lines.firstIndex { $0.contains("shower.action startNext") })
        XCTAssertFalse(lines[..<nextAt].contains { $0.contains("ble.close") || $0.contains("lxt.settle") },
                       "nothing closed or settled for the stopped shower")
        let file = try String(contentsOf: log.eventsFile, encoding: .utf8)
        let all = lines.joined(separator: "\n") + "\n" + file
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: all), [])
        XCTAssertEqual(log.droppedCount, 0, "the last check never had to drop a line")
        for l in lines { XCTAssertTrue(DebugLogScreen.isSafe(l), l) }

        // The file a tester would export from 高级.
        let exported = DebugLogExport.text(lines)
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: exported), [])
        let salt = try Data(contentsOf: log.saltFile).map { String(format: "%02x", $0) }.joined()
        XCTAssertFalse(exported.lowercased().contains(salt))
        print("=== SAMPLE EXPORT BEGIN ===\n\(exported)=== SAMPLE EXPORT END ===")
    }

    /// 55 from another controller, A5 and a frame nobody can read: each as its type and length.
    func testEachProbeAnswerIsItsTypeLengthAndVerdict() async throws {
        let cases: [(Data, String)] = [
            (FakeFrames.identity("99887766"), "ble.probe type=55 len=20 verdict=idleOther"),
            (FakeFrames.active, "ble.probe type=A5 len=1 verdict=active"),
            (Data([0x12, 0x34, 0x56]), "ble.probe type=other len=3 verdict=unreadable"),
        ]
        for (frame, expected) in cases {
            vault = StoredShowerVault(store: InMemorySecureStore())
            transport = FakeShowerTransport()
            let log = RecordingDebugLog()
            let e = try engine(FakeGateway(), log: log)
            transport.script(.frame(frame))
            _ = try? await e.start(binding)
            XCTAssertTrue(log.lines().contains(expected), "\(expected)\n" + log.lines().joined(separator: "\n"))
            XCTAssertFalse(log.lines().contains { $0.hasPrefix("lxt.authorize") }, "nothing was authorized")
            XCTAssertEqual(DebugLogTesting.leaks(["99887766", machine, "123456"], in: log.lines().joined()), [])
        }
    }

    func testAConnectFailureIsItsDeviceError() async throws {
        let log = RecordingDebugLog()
        let e = try engine(FakeGateway(), log: log)
        transport.scriptConnect(.failure(.notFound))
        _ = try? await e.start(binding)
        XCTAssertTrue(log.lines().contains("ble.connect result=notFound target=scanned"), log.lines().joined(separator: "\n"))
    }

    /// An App Store, Xcode or sample run: the same shower, no folder, no file.
    func testWithoutTheLogAShowerCreatesNothing() async throws {
        let log = LaunchDebugLog(applicationSupport: folder, now: clock.function)
        log.resolve(.appStore)
        try await fullShower(log)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    /// A log that can't be written never stops or changes a shower.
    func testAnUnwritableLogNeverStopsTheShower() async throws {
        let blocker = folder.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let log = FileDebugLog(directory: blocker.appendingPathComponent("DebugLog"), now: clock.function, timeZone: utc)
        try await fullShower(log)
        XCTAssertEqual(try vault.showerState()?.phase, .idle)
    }

    /// At launch: what was saved and what it is now.
    func testTheRecordFoundAtLaunchIsLogged() throws {
        var settling = ShowerState(phase: .settling, machineID: machine, peripheralID: "PERIPHERAL-A", authorizeSent: true,
                                   authorizationID: "A1B2C3D4")
        settling.consumption = HexCoding.upper(consumption)
        try vault.saveShowerState(settling)
        let log = RecordingDebugLog()
        _ = try engine(FakeGateway(), log: log)
        XCTAssertEqual(log.events.first, .showerRestore(saved: .settling, restored: .failed, unreadable: false))
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: log.lines().joined()), [])
    }

    /// 开始洗澡 from Siri over a shower that is over goes the 开始下一次洗澡 way, and says so; a
    /// controller still in use sends nothing.
    func testAShortcutStartOverAStoppedShowerIsTheNextShower() async throws {
        let log = RecordingDebugLog()
        let gateway = FakeGateway()
        gateway.scriptAuthorize(.ok(ShowerAuthorization(machineID: machine, payload: Data(repeating: 0x30, count: 15), authorizationID: "AABBCCDD")))
        let e = try engine(gateway, log: log)
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        _ = try await e.startOrNext(binding)
        transport.script(.frame(identity))
        _ = try await e.finish(binding)
        transport.script(.frame(FakeFrames.active))
        let busy = try await e.startOrNext(binding)
        XCTAssertTrue(busy.waitingForRelease)
        let lines = log.lines()
        XCTAssertEqual(lines.filter { $0.hasPrefix("shower.action shortcutStart") },
                       ["shower.action shortcutStart next=no", "shower.action shortcutStart next=yes"], lines.joined(separator: "\n"))
        XCTAssertTrue(lines.contains("shower.note nextUse.deviceBusy"), lines.joined(separator: "\n"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("lxt.authorize sent") }.count, 1, "nothing authorized over the busy controller")
        XCTAssertEqual(DebugLogTesting.leaks(secrets + ["AABBCCDD"], in: lines.joined()), [])
    }

    /// The stopped shower can't be kept: nothing is authorized, and the log says why.
    func testANextShowerWhoseRecordCantBeKeptSaysSo() async throws {
        let log = RecordingDebugLog()
        let gateway = FakeGateway()
        gateway.scriptAuthorize(.ok(ShowerAuthorization(machineID: machine, payload: Data(repeating: 0x30, count: 15), authorizationID: "AABBCCDD")))
        let flaky = FlakyShowerVault()
        let e = try ShowerEngine(transport: transport, gateway: gateway, vault: flaky, configuration: .init(bleName: "fixture-ble"),
                                 hooks: DebugLogShowerHooks(log), now: clock.function)
        transport.script(.frame(identity), .frame(FakeFrames.ack))
        _ = try await e.start(binding)
        transport.script(.frame(identity))
        _ = try await e.finish(binding)
        flaky.failRetain = true
        transport.script(.frame(identity))
        _ = try? await e.startNext(binding)
        XCTAssertTrue(log.lines().contains("shower.note nextUse.keepFailed"), log.lines().joined(separator: "\n"))
        XCTAssertFalse(log.lines().contains("shower.note nextUse.recordKept.readBackOK"))
        XCTAssertEqual(gateway.authorizeFrames.count, 1)
    }

    /// 取消 while connecting is logged with whether it was taken.
    func testACancelledStartIsLogged() async throws {
        let log = RecordingDebugLog()
        let e = try engine(FakeGateway(), log: log)
        transport.script(.hang)
        let b = binding
        let task = Task { try? await e.start(b) }
        await eventually { [transport] in transport!.writes.count == 1 }
        let accepted = await e.cancelStart()
        XCTAssertTrue(accepted)
        task.cancel()
        _ = await task.value
        XCTAssertTrue(log.events.contains(.showerAction(.cancelStart(accepted: true))))
    }
}
