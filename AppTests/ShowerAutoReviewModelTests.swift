import XCTest
import Core
@testable import XiaoRiChang

/// The live model's automatic check while the app is in front (`ShowerModel.autoReviewIfDue`),
/// and the ways in to 结束 over a close the controller answered busy. On fake stores and a
/// scripted controller: nothing real is read or sent.
@MainActor
final class ShowerAutoReviewModelTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func model(record: ShowerState, transport: ScriptedControllerLink, http: HeldHTTP = HeldHTTP(),
               gate: LiveShowerGate = LiveShowerGate()) async throws -> ShowerModel {
        let store = ScriptedStore()
        let vault = StoredShowerVault(store: store)
        try vault.saveBinding(Fixture.binding)
        try vault.saveShowerState(record)
        let services = CampusServices(kind: .live, secureStore: store, defaults: SampleDefaults(), sharedPreferences: nil,
                                      schoolHTTP: SampleHTTPClient(), showerHTTP: http, laundryHTTP: SampleHTTPClient(),
                                      feedbackHTTP: nil, showerTransport: transport, leaseFile: nil,
                                      applicationSupport: try Fixture.supportWithProfile(), sharedDidChange: {})
        let model = ShowerModel(services: services, reminders: .sample(defaults: services.defaults), activities: nil, gate: gate)
        await model.reloadProfile()
        await waitUntil { model.gateRecord != .notLoaded }
        return model
    }

    var running: ShowerState {
        ShowerState(phase: .running, machineID: "11223344", peripheralID: "P", startedAt: t0, authorizeSent: true, authorizationID: "001122FF")
    }

    /// The attempt counts from its start, before the controller answers, and a failed one counts
    /// too: a controller out of reach is not tried every tick.
    func testFailuresStillCountTowardTheInterval() async throws {
        let link = ScriptedControllerLink()
        link.failConnects = true
        let model = try await model(record: running, transport: link)
        let a = await model.autoReviewIfDue(now: t0)
        XCTAssertTrue(a)
        XCTAssertEqual(model.lastAutoReview, t0)
        XCTAssertEqual(link.connects, 1)
        for seconds in [5.0, 10, 29] {
            let again = await model.autoReviewIfDue(now: t0.addingTimeInterval(seconds))
            XCTAssertFalse(again, "\(seconds)")
        }
        XCTAssertEqual(link.connects, 1)
        let later = await model.autoReviewIfDue(now: t0.addingTimeInterval(30))
        XCTAssertTrue(later)
        XCTAssertEqual(link.connects, 2)
        XCTAssertEqual(model.state.phase, .running)
        XCTAssertNil(model.message, "an automatic check says nothing when it fails")
    }

    /// Recorded before the await: while the probe is out, a second tick does not start another.
    func testTheAttemptIsRecordedBeforeTheProbeAnswers() async throws {
        let link = ScriptedControllerLink()
        link.holdExchange = true
        let model = try await model(record: running, transport: link)
        let first = Task { await model.autoReviewIfDue(now: t0) }
        await waitUntil { link.isHolding }
        XCTAssertEqual(model.lastAutoReview, t0)
        let second = await model.autoReviewIfDue(now: t0.addingTimeInterval(31))
        XCTAssertFalse(second, "busy: skipped")
        link.release(FakeFramesApp.active)
        let ran = await first.value
        XCTAssertTrue(ran)
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand])
    }

    /// Something else under way: skipped without waiting, and the skip does not count.
    func testAutoReviewSkipsWhenBusyOrLiveStepTaken() async throws {
        let link = ScriptedControllerLink()
        link.holdExchange = true
        let model = try await model(record: running, transport: link)
        let manual = Task { await model.reviewCurrentSession() }
        await waitUntil { model.busy && link.isHolding }
        let skipped = await model.autoReviewIfDue(now: t0)
        XCTAssertFalse(skipped)
        XCTAssertNil(model.lastAutoReview, "a skip is not an attempt")
        link.release(FakeFramesApp.active)
        await manual.value
        XCTAssertEqual(link.writes.count, 1)

        let ran = await model.autoReviewIfDue(now: t0)
        XCTAssertTrue(ran)
    }

    /// While the sample is shown no live step begins, the automatic check included.
    func testNoAutoReviewWhileTheSampleIsShown() async throws {
        let link = ScriptedControllerLink()
        let gate = LiveShowerGate()
        let model = try await model(record: running, transport: link, gate: gate)
        // The sample is on (the gate is told the record is at rest only to let it open here).
        gate.record = { .known(.idle) }
        let sample = SampleMode(gate: gate)
        XCTAssertEqual(sample.enter(), .entered)
        let ran = await model.autoReviewIfDue(now: t0)
        XCTAssertFalse(ran)
        XCTAssertNil(model.lastAutoReview)
        XCTAssertEqual(link.connects, 0)
        XCTAssertTrue(link.writes.isEmpty)
    }

    /// Only `AA` goes out: water still running keeps the link, nothing reaches the platform.
    func testOnlyTheProbeGoesOutAndA5KeepsTheLink() async throws {
        let link = ScriptedControllerLink()
        link.replies = [FakeFramesApp.active]
        let http = HeldHTTP()
        let model = try await model(record: running, transport: link, http: http)
        let ran = await model.autoReviewIfDue(now: t0)
        XCTAssertTrue(ran)
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand])
        XCTAssertEqual(link.disconnects, 0, "A5 keeps the connection")
        XCTAssertEqual(http.sent, 0)
        XCTAssertEqual(model.state.phase, .running)
    }

    /// Records that wait for something are never checked by themselves.
    func testNoAutoReviewOverAKeptOrUnsureRecord() async throws {
        var busyClose = running
        busyClose.phase = .failed; busyClose.closeSent = true
        busyClose.failure = ShowerFailure(reason: .closeBusy, needsReview: true)
        var unsure = busyClose
        unsure.failure = ShowerFailure(reason: .closeUnconfirmed, needsReview: true)
        var stopped = running; stopped.stateReviewRequired = true
        var notWritten = running; notWritten.phase = .writePending; notWritten.authorizationNotWritten = true
        for record in [busyClose, unsure, stopped, notWritten, ShowerState.idle] {
            let link = ScriptedControllerLink()
            let model = try await model(record: record, transport: link)
            let ran = await model.autoReviewIfDue(now: t0)
            XCTAssertFalse(ran, "\(record.phase)")
            XCTAssertEqual(link.connects, 0)
        }
    }

    /// 结束 over a close answered busy: every way in (the page, Siri, the Live Activity, all
    /// through `run(start: false)`) is refused before anything goes out.
    func testNoEntryEndsACloseAnsweredBusy() async throws {
        var busyClose = running
        busyClose.phase = .failed; busyClose.closeSent = true
        busyClose.failure = ShowerFailure(reason: .closeBusy, needsReview: true)
        let link = ScriptedControllerLink()
        let http = HeldHTTP()
        let model = try await model(record: busyClose, transport: link, http: http)
        XCTAssertFalse(model.mayFinish)
        XCTAssertFalse(model.page.mayEnd)
        do {
            try await model.run(start: false)
            XCTFail("refused")
        } catch {}
        model.pageEvent(.endTapped)
        await pause(50)
        // A check that finds water running leaves it as it is.
        link.replies = [FakeFramesApp.active]
        await model.reviewCurrentSession()
        XCTAssertEqual(model.state.failure?.reason, .closeBusy)
        XCTAssertFalse(model.mayFinish)
        XCTAssertEqual(model.message, "水控还在出水，这次没再发结束，免得关掉别人的水。是你的水的话，在水控上按停。")
        do {
            try await model.run(start: false)
            XCTFail("refused")
        } catch {}
        XCTAssertEqual(link.writes, [ShowerFrames.probeCommand], "only the check's probe")
        XCTAssertEqual(http.sent, 0)
    }
}

enum FakeFramesApp {
    static let active = Data([0xA5])
}

/// A controller link that records what it was asked and answers from a script. `holdExchange`:
/// the next exchange waits for `release`.
final class ScriptedControllerLink: ShowerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _writes: [Data] = []
    private var _connects = 0
    private var _disconnects = 0
    private var _replies: [Data] = []
    private var _failConnects = false
    private var _hold = false
    private var held: CheckedContinuation<Data, Never>?

    var writes: [Data] { lock.withLock { _writes } }
    var isHolding: Bool { lock.withLock { held != nil } }
    var connects: Int { lock.withLock { _connects } }
    var disconnects: Int { lock.withLock { _disconnects } }
    var replies: [Data] {
        get { lock.withLock { _replies } }
        set { lock.withLock { _replies = newValue } }
    }
    var failConnects: Bool {
        get { lock.withLock { _failConnects } }
        set { lock.withLock { _failConnects = newValue } }
    }
    var holdExchange: Bool {
        get { lock.withLock { _hold } }
        set { lock.withLock { _hold = newValue } }
    }

    func connect(bleName: String, machineID: String, required: String?, preferred: String?) async throws -> String {
        let fail = lock.withLock { _connects += 1; return _failConnects }
        if fail { throw ShowerDeviceError.notFound }
        return required ?? preferred ?? "P"
    }

    func exchange(_ command: Data) async throws -> Data {
        let (hold, reply): (Bool, Data?) = lock.withLock {
            _writes.append(command)
            if _hold { _hold = false; return (true, nil) }
            return (false, _replies.isEmpty ? nil : _replies.removeFirst())
        }
        if hold { return await withCheckedContinuation { c in lock.withLock { held = c } } }
        guard let reply else { throw ShowerDeviceError.timedOut }
        return reply
    }

    func release(_ frame: Data) {
        let c: CheckedContinuation<Data, Never>? = lock.withLock { defer { held = nil }; return held }
        c?.resume(returning: frame)
    }

    func disconnect() async { lock.withLock { _disconnects += 1 } }
}
