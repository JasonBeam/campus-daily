import XCTest
import Foundation
import Core
import CoreTestSupport

/// Every event the app can log passes the log's last check (`DebugLogScreen`), so none of them
/// is ever written as `<dropped>`. `Kind` is the list of events: `kind(of:)` has no default, so
/// a new event does not compile until it is named here, and then fails until it has samples.
final class DebugEventScreenTests: XCTestCase {
    enum Kind: CaseIterable {
        case showerAction, showerPhase, showerRestore, showerNote, bleConnect, bleProbe, bleAuthWrite, bleClose
        case lxtAuthorize, lxtSettle
        case laundryPhase, laundryRequest, laundryOrder, laundryPayLaunch, laundryStart
        case schoolRefresh, schoolCredentialExpired, schoolSavedLogin, schoolRenew, ujingLogin
        case http, navOpen
    }

    static func kind(of event: DebugEvent) -> Kind {
        switch event {
        case .showerAction: return .showerAction
        case .showerPhase: return .showerPhase
        case .showerRestore: return .showerRestore
        case .showerNote: return .showerNote
        case .bleConnect: return .bleConnect
        case .bleProbe: return .bleProbe
        case .bleAuthWrite: return .bleAuthWrite
        case .bleClose: return .bleClose
        case .lxtAuthorize: return .lxtAuthorize
        case .lxtSettle: return .lxtSettle
        case .laundryPhase: return .laundryPhase
        case .laundryRequest: return .laundryRequest
        case .laundryOrder: return .laundryOrder
        case .laundryPayLaunch: return .laundryPayLaunch
        case .laundryStart: return .laundryStart
        case .schoolRefresh: return .schoolRefresh
        case .schoolCredentialExpired: return .schoolCredentialExpired
        case .schoolSavedLogin: return .schoolSavedLogin
        case .schoolRenew: return .schoolRenew
        case .ujingLogin: return .ujingLogin
        case .http: return .http
        case .navOpen: return .navOpen
        }
    }

    static let machine = DebugTag(.machine, "11223344")
    static let washer = DebugTag(.washer, "W-1")
    static let order = DebugTag(.order, "458000")
    static let devices: [ShowerDeviceError] = [.bluetoothOff, .notFound, .ambiguous, .timedOut, .disconnected, .malformedFrame, .interrupted, .busy]
    static let reasons: [ShowerFailureReason] = [.deviceUnavailable, .wrongDevice, .deviceBusy, .authorizeRefused, .authorizeUncertain,
                                                 .authorizationInvalid, .closeUnconfirmed, .settleRefused, .settleUncertain, .settleUnconfirmed]
    static let codes = [DebugCode("4002"), DebugCode("HTTP 502"), DebugCode("-1"), DebugCode("12345678")]
    static let failures: [ServiceError] = [.offline, .timedOut, .tls, .sessionExpired(.ujing), .badRequest(.lxt6),
                                           .malformed(.ecykt, "data.result"), .uncertain(.portal),
                                           .rejected(.lxt6, code: "4002", message: "重复结算 password secret 12345678")]
    static var errors: [DebugError] { failures.map(DebugError.init) + [DebugError(CocoaError(.fileNoSuchFile))] }
    static var outcomes: [DebugOutcome] { [.ok] + errors.map(DebugOutcome.failed) }
    static var schoolOutcomes: [DebugSchoolOutcome] {
        [.ok, .notSignedIn, .leaseLost, .interrupted] + errors.flatMap { [.needsLogin($0), .failed($0)] }
    }
    static let frames: [DebugFrame] = [Data([0x55] + Array(repeating: 0x11, count: 19)), Data([0xAA] + Array(repeating: 0, count: 8)),
                                       Data([0xA5]), Data([0x12, 0x34]), Data()].map(DebugFrame.init)
    static var writes: [DebugWrite] {
        [.notSent] + devices.map(DebugWrite.failed) + frames.flatMap { [DebugWrite.replied($0, matches: true), .replied($0, matches: false)] }
    }

    static var showerStates: [DebugShowerState] {
        var states = ShowerPhase.allCases.map { DebugShowerState(ShowerState(phase: $0)) }
        for reason in reasons {
            var s = DebugShowerState(ShowerState(phase: .failed))
            s.failure = reason; s.deviceError = .timedOut; s.errorKind = .rejected
            s.needsReview = true; s.settleNotSent = true; s.settleHeld = true; s.holdSettle = true
            s.stateReviewRequired = true; s.waitingForRelease = true; s.authorizationNotWritten = true
            s.reviewing = true; s.showerOver = true
            states.append(s)
        }
        for notice in [DebugShowerState.Notice.device, .notActive, .wrongDevice, .writeUnconfirmed, .inUseByOther] {
            var s = DebugShowerState(ShowerState(phase: .running))
            s.notice = notice; s.noticeDevice = notice == .device ? .disconnected : nil
            states.append(s)
        }
        return states
    }

    static var notes: [ShowerDiagnostic] {
        [.nextUseDeviceBusy, .nextUseWrongDevice, .nextUseUnreadable, .nextUseCancelled, .nextUseRecordKept, .nextUseKeepFailed,
         .nextUseNotSaved, .reviewWriteNeverApplied, .finishWriteNeverApplied, .settleHeldAfterUnconfirmedClose,
         .settleManualRetry(1), .settleManualRetry(12)] + ShowerPhase.allCases.map(ShowerDiagnostic.resolvedManually)
    }

    static var laundryStarts: [DebugLaundryStart] {
        let skips: [DebugStartSkip] = [.notFront, .cancelled, .expired, .account, .unsupported, .offline, .selfClean, .dispenser,
                                       .otherOrder, .status, .price, .notSaved]
        let checks: [DebugLaundryStart] = [DebugPriceCheck.ok, .mismatch, .unreadable].flatMap { price in
            codes.map { DebugLaundryStart.check(paid: true, status: $0, price: price, moduleType: 7, order: order) }
        } + [.check(paid: false, status: DebugCode("10"), price: .unreadable, moduleType: nil, order: nil)]
        return [.chosen(immediate: true), .chosen(immediate: false), .returned(inFront: true), .returned(inFront: false), .saved, .handed]
            + checks
            + [.result(.ok), .result(.refused(nil))] + codes.map { .result(.refused($0)) }
            + failures.map { .result(.unknown(DebugErrorKind($0))) }
            + skips.map(DebugLaundryStart.skipped)
    }

    static var https: [DebugHTTP] {
        let hosts = ["cas.example.edu.cn", "isv.lxt6.cn", "unknown.example.com"]
        var entries = DebugHTTPName.allCases.map {
            HTTPLogEntry(service: .ujing, method: "POST", host: "u.zhinengxiyifang.cn", name: $0.rawValue, status: 200, milliseconds: 153,
                         code: "0", error: nil)
        }
        for service in Service.allCases {
            for host in hosts {
                entries.append(HTTPLogEntry(service: service, method: "GET", host: host, name: "csalogintoken", status: nil,
                                            milliseconds: 30_000, code: nil, error: "timedOut"))
                entries.append(HTTPLogEntry(service: service, method: "GET", host: host, name: "someUnknownName", status: 502,
                                            milliseconds: 9, code: "HTTP 502", error: "transport"))
            }
        }
        return entries.map(DebugHTTP.init)
    }

    /// Representative values for every event, every variant of each where there are few.
    static var samples: [DebugEvent] {
        var e: [DebugEvent] = []
        e += [DebugShowerAction.start(machine: machine), .startNext(machine: machine), .shortcutStart(next: true),
              .shortcutStart(next: false), .finish, .review, .dismiss, .cancelStart(accepted: true), .cancelStart(accepted: false)]
            .map(DebugEvent.showerAction)
        e += ShowerPhase.allCases.flatMap { from in showerStates.map { DebugEvent.showerPhase(from: from, to: $0) } }
        e += ([nil] + ShowerPhase.allCases).flatMap { saved in
            ShowerPhase.allCases.flatMap { restored in [true, false].map { DebugEvent.showerRestore(saved: saved, restored: restored, unreadable: $0) } }
        }
        e += notes.map(DebugEvent.showerNote)
        e += ([nil] + devices).flatMap { error in
            [DebugConnect.Target.required, .preferred, .scanned].flatMap { target in
                [nil, true, false].map { DebugEvent.bleConnect(DebugConnect(error: error, target: target, samePeripheral: $0)) }
            }
        }
        e += frames.flatMap { f in [DebugProbeVerdict.idleSelf, .idleOther, .active, .unreadable].map { DebugEvent.bleProbe(f, $0) } }
        e += writes.map(DebugEvent.bleAuthWrite)
        e += writes.map(DebugEvent.bleClose)
        e += ([.sent, .notSent, .ok(dataLength: 15, idIsHex8: true), .ok(dataLength: 0, idIsHex8: false)] + errors.map(DebugAuthorizeStep.failed))
            .map(DebugEvent.lxtAuthorize)
        e += ([.sent, .notSent, .ok(fen: 163), .ok(fen: nil)] + errors.map(DebugSettleStep.failed)).map(DebugEvent.lxtSettle)
        e += LaundryPhase.allCases.flatMap { from in
            LaundryPhase.allCases.flatMap { to in ([nil] + codes).map { DebugEvent.laundryPhase(from: from, to: to, outcome: $0) } }
        }
        e += [DebugLaundryRequest.create, .orderDetail, .paymentMethods, .paymentArguments, .cancelOrder, .findActive, .startCheck, .startWasher]
            .flatMap { name in outcomes.map { DebugEvent.laundryRequest(name, $0) } }
        e += codes.flatMap { status in [DebugEvent.laundryOrder(status: status, moduleType: 7, order: order),
                                        .laundryOrder(status: status, moduleType: nil, order: nil)] }
        e += [DebugEvent.laundryPayLaunch(opened: true), .laundryPayLaunch(opened: false)]
        e += laundryStarts.map(DebugEvent.laundryStart)
        e += schoolOutcomes.map(DebugEvent.schoolRefresh)
        e += schoolOutcomes.map(DebugEvent.schoolRenew)
        e += [DebugCredential.card, .portal].flatMap { kind in
            [DebugEvent.schoolCredentialExpired(kind: kind, ageMinutes: 152, aliveMinutes: 92),
             .schoolCredentialExpired(kind: kind, ageMinutes: nil, aliveMinutes: nil)]
        }
        let reasons: [DebugPasswordStep.Reason] = [.noLoginDeviceID, .credentialsChanged, .deviceIDNotSaved]
        e += ([DebugPasswordStep.sent] + reasons.map(DebugPasswordStep.deferred) + reasons.map(DebugPasswordStep.skipped))
            .map(DebugEvent.schoolSavedLogin)
        e += outcomes.map(DebugEvent.ujingLogin)
        e += https.map(DebugEvent.http)
        e += DebugPage.allCases.flatMap { page in DebugEntry.allCases.map { DebugEvent.navOpen(page, from: $0) } }
        e.append(.laundryOrder(status: DebugCode("20"), moduleType: 7, order: washer))
        return e
    }

    func testEveryEventHasSamples() {
        let covered = Set(Self.samples.map(Self.kind(of:)))
        for kind in Kind.allCases {
            XCTAssertTrue(covered.contains(kind), "no sample for \(kind)")
        }
    }

    /// The line as the log writes it (`FileDebugLog.record`), each tag as `kind:` and 6 hex.
    func testEveryEventsLinePassesTheScreen() {
        for event in Self.samples {
            let fields = event.fields { "\($0.kind.rawValue):3fa2c1" }
            let line = "10-30 04:00:00 " + (fields.isEmpty ? event.name : "\(event.name) \(fields)")
            XCTAssertTrue(DebugLogScreen.isSafe(line), line)
        }
    }

    /// The same events through the file log itself: none is replaced.
    func testNoEventIsDroppedByTheFileLog() throws {
        let folder = DebugLogTesting.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = FileDebugLog(directory: folder.appendingPathComponent("DebugLog"), maxLines: 100_000, maxBytes: 64 * 1024 * 1024)
        let samples = Self.samples
        for event in samples { log.record(event) }
        log.flush()
        let lines = log.lines()
        XCTAssertEqual(lines.count, samples.count)
        let dropped = zip(samples, lines).filter { $0.1.hasSuffix(DebugLogScreen.dropped) }.map { "\($0.0)" }
        XCTAssertEqual(dropped, [])
    }
}
