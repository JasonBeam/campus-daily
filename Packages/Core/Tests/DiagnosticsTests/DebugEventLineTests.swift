import XCTest
import Foundation
import Core
import CoreTestSupport

/// What each event writes: fixed words, numbers, flags and tags, never a value.
final class DebugEventLineTests: XCTestCase {
    let machine = "11223344"
    func line(_ e: DebugEvent) -> String { e.fields { "\($0.kind.rawValue):tag" } }

    /// 55 / AA / A5 / an unknown frame: only the first byte, the length and the verdict.
    func testFramesShowOnlyTheirTypeAndLength() {
        let mine = FakeFrames.identity(machine, tail: 0x40)
        let other = FakeFrames.identity("99887766", tail: 0x40)
        let junk = Data([0x12, 0x34, 0x56])
        XCTAssertEqual(line(.bleProbe(DebugFrame(mine), DebugProbeVerdict(mine, machineID: machine))), "type=55 len=20 verdict=idleSelf")
        XCTAssertEqual(line(.bleProbe(DebugFrame(mine), DebugProbeVerdict(mine, machineID: "aabbccdd"))), "type=55 len=20 verdict=idleOther")
        XCTAssertEqual(line(.bleProbe(DebugFrame(other), DebugProbeVerdict(other, machineID: machine))), "type=55 len=20 verdict=idleOther")
        XCTAssertEqual(line(.bleProbe(DebugFrame(FakeFrames.active), DebugProbeVerdict(FakeFrames.active, machineID: machine))),
                       "type=A5 len=1 verdict=active")
        XCTAssertEqual(line(.bleProbe(DebugFrame(junk), DebugProbeVerdict(junk, machineID: machine))), "type=other len=3 verdict=unreadable")
        XCTAssertEqual(line(.bleProbe(DebugFrame(Data()), .unreadable)), "type=empty len=0 verdict=unreadable")
        XCTAssertEqual(line(.bleAuthWrite(.replied(DebugFrame(FakeFrames.ack), matches: true))), "out=15 replied type=AA len=9 ack=yes")
        XCTAssertEqual(line(.bleAuthWrite(.notSent)), "out=15 notSent")
        XCTAssertEqual(line(.bleClose(.replied(DebugFrame(mine), matches: true))), "replied type=55 len=20 consumption=yes")
        XCTAssertEqual(line(.bleClose(.failed(.timedOut))), "failed device=timedOut")
        let all = [mine, other, junk].map { line(.bleProbe(DebugFrame($0), DebugProbeVerdict($0, machineID: machine))) }.joined()
        XCTAssertTrue(DebugLogTesting.leaks([machine, "99887766", "40414243", "123456"], in: all).isEmpty)
    }

    func testCodesAreShortWordsOrOther() {
        XCTAssertEqual(DebugCode("4002").text, "4002")
        XCTAssertEqual(DebugCode("HTTP 502").text, "HTTP_502")
        XCTAssertEqual(DebugCode("-1").text, "-1")
        XCTAssertEqual(DebugCode("12345678").text, "other", "an id-length number is not a code")
        XCTAssertEqual(DebugCode("ABCDEFGHIJKLM").text, "other", "more than 12")
        XCTAssertEqual(DebugCode("重复").text, "other")
        XCTAssertEqual(DebugCode("a=b").text, "other")
        XCTAssertEqual(DebugCode("").text, "other")
    }

    /// The server's sentence and the field path never make it into a line.
    func testAnErrorKeepsItsKindServiceAndCodeOnly() {
        let rejected = DebugError(ServiceError.rejected(.lxt6, code: "3", message: "重复结算 S1234567"))
        XCTAssertEqual(line(.lxtSettle(.failed(rejected))), "failed kind=rejected service=lxt6 code=3")
        XCTAssertEqual(line(.lxtAuthorize(.failed(DebugError(ServiceError.malformed(.lxt6, "data.studentId"))))),
                       "failed kind=malformed service=lxt6")
        XCTAssertEqual(line(.ujingLogin(DebugOutcome(ServiceError.timedOut))), "failed kind=timedOut")
        XCTAssertEqual(line(.ujingLogin(DebugOutcome(CocoaError(.fileNoSuchFile)))), "failed kind=other")
        XCTAssertEqual(line(.ujingLogin(DebugOutcome(nil))), "ok")
    }

    func testAnHTTPLineKeepsKnownNamesHostsAndErrors() {
        func h(_ name: String, host: String = "isv.lxt6.cn", error: String? = nil) -> String {
            line(.http(DebugHTTP(HTTPLogEntry(service: .lxt6, method: "POST", host: host, name: name, status: error == nil ? 200 : nil,
                                             milliseconds: 153, code: error == nil ? "0" : nil, error: error))))
        }
        XCTAssertEqual(h("authorize"), "lxt6 POST host=lxt6 name=authorize status=200 ms=153 code=0")
        XCTAssertEqual(h("A1B2C3D4"), "lxt6 POST host=lxt6 name=other status=200 ms=153 code=0")
        XCTAssertEqual(h("settle", host: "evil.example"), "lxt6 POST host=other name=settle status=200 ms=153 code=0")
        XCTAssertEqual(h("settle", error: "timedOut"), "lxt6 POST host=lxt6 name=settle ms=153 error=timedOut")
        XCTAssertEqual(h("settle", error: "rejected(lxt6, \"3\", \"重复结算\")"), "lxt6 POST host=lxt6 name=settle ms=153 error=other")
    }

    func testAShowerPhaseLineHasTheFlagsAndNoIds() {
        var s = ShowerState(phase: .failed, machineID: machine, peripheralID: "PERIPHERAL-A", authorizeSent: true, authorizationID: "A1B2C3D4")
        s.failure = ShowerFailure(reason: .settleRefused, needsReview: true, error: .rejected(.lxt6, code: "3", message: "重复结算"))
        let text = line(.showerPhase(from: .settling, to: DebugShowerState(s)))
        XCTAssertEqual(text, "from=settling to=failed failure=settleRefused error=rejected needsReview showerOver")
        XCTAssertTrue(DebugLogTesting.leaks([machine, "PERIPHERAL", "A1B2C3D4", "重复结算"], in: text).isEmpty)
    }

    func testEveryNoteKeepsItsOldName() {
        XCTAssertEqual(DebugEvent.showerNote(.settleManualRetry(2)).name, "shower.note")
        XCTAssertEqual(line(.showerNote(.settleManualRetry(2))), "settle.manualRetry#2")
        XCTAssertEqual(line(.showerNote(.resolvedManually(.failed))), "resolvedManually.failed")
        XCTAssertEqual(line(.showerNote(.nextUseDeviceBusy)), "nextUse.deviceBusy")
        XCTAssertEqual(line(.showerNote(.nextUseRecordKept)), "nextUse.recordKept.readBackOK")
        XCTAssertEqual(line(.showerNote(.nextUseKeepFailed)), "nextUse.keepFailed")
        XCTAssertEqual(line(.showerNote(.nextUseNotSaved)), "nextUse.newRecordNotSaved")
    }

    /// 开始洗澡 from Siri or Shortcuts says which way it went.
    func testAShortcutStartSaysWhetherItWasTheNextShower() {
        XCTAssertEqual(line(.showerAction(.shortcutStart(next: true))), "shortcutStart next=yes")
        XCTAssertEqual(line(.showerAction(.shortcutStart(next: false))), "shortcutStart next=no")
    }

    func testANavLineIsAPageAndAnEntry() {
        XCTAssertEqual(DebugEvent.navOpen(.feedback, from: .settings).name, "nav.open")
        XCTAssertEqual(line(.navOpen(.feedback, from: .settings)), "page=feedback from=settings")
    }
}

/// `nav.open`: the page, and the entry it was opened from when that was said just before.
final class DebugNavTests: XCTestCase {
    let clock = FakeClock(Date(timeIntervalSince1970: 1_793_332_800))

    func testAPageOpenedOnItsOwnUsesItsDefaultEntry() {
        let log = RecordingDebugLog()
        let nav = DebugNav(log: log, now: clock.function)
        nav.opened(.laundry, default: .homeButton)
        XCTAssertEqual(log.events, [.navOpen(.laundry, from: .homeButton)])
    }

    func testAnEntrySaidJustBeforeIsUsedOnce() {
        let log = RecordingDebugLog()
        let nav = DebugNav(log: log, now: clock.function)
        nav.from(.widget)
        clock.advance(1)
        nav.opened(.showerPage, default: .homeButton)
        nav.opened(.showerDetail, default: .pageEvent)
        XCTAssertEqual(log.events, [.navOpen(.showerPage, from: .widget), .navOpen(.showerDetail, from: .pageEvent)])
    }

    func testAnOldEntryIsNotUsed() {
        let log = RecordingDebugLog()
        let nav = DebugNav(log: log, now: clock.function)
        nav.from(.notification)
        clock.advance(DebugNav.pendingLifetime + 1)
        nav.opened(.laundry, default: .homeButton)
        XCTAssertEqual(log.events, [.navOpen(.laundry, from: .homeButton)])
    }

    /// An entry for named pages waits for them: a tab appearing on the way is not given it.
    func testAnEntryForNamedPagesGoesToEachOfThemOnce() {
        let log = RecordingDebugLog()
        let nav = DebugNav(log: log, now: clock.function)
        nav.from(.widget, to: [.settings, .account])
        nav.opened(.home, default: .tab)
        nav.opened(.settings, default: .tab)
        nav.opened(.account, default: .settings)
        nav.opened(.account, default: .settings)
        XCTAssertEqual(log.events, [.navOpen(.home, from: .tab), .navOpen(.settings, from: .widget),
                                    .navOpen(.account, from: .widget), .navOpen(.account, from: .settings)])
    }

    /// The page raising itself says `pageEvent` only when nothing said why first (a tap, a
    /// Shortcut): the reason given first wins.
    func testAPageEventDoesNotReplaceAReasonGivenFirst() {
        let log = RecordingDebugLog()
        let nav = DebugNav(log: log, now: clock.function)
        nav.from(.homeButton, to: [.showerPage])
        nav.from(.pageEvent, to: [.showerPage], unlessPending: true)
        nav.opened(.showerPage, default: .pageEvent)
        nav.from(.pageEvent, to: [.showerPage], unlessPending: true)
        nav.opened(.showerPage, default: .homeButton)
        XCTAssertEqual(log.events, [.navOpen(.showerPage, from: .homeButton), .navOpen(.showerPage, from: .pageEvent)])
    }

    /// The newest reason for a page wins over an older one still waiting.
    func testTheNewestEntryForAPageWins() {
        let log = RecordingDebugLog()
        let nav = DebugNav(log: log, now: clock.function)
        nav.from(.notification, to: [.laundry])
        clock.advance(1)
        nav.from(.widget, to: [.laundry])
        nav.opened(.laundry, default: .homeButton)
        nav.opened(.laundry, default: .homeButton)
        XCTAssertEqual(log.events, [.navOpen(.laundry, from: .widget), .navOpen(.laundry, from: .homeButton)])
    }

    /// Every way in that is not a tap has a name of its own.
    func testProgrammaticEntriesHaveTheirOwnNames() {
        let names = Set(DebugEntry.allCases.map(\.rawValue))
        for name in ["recents", "pageEvent", "restore", "reset", "sample", "alert", "updateLine", "setupDone",
                     "widget", "notification", "intent", "liveActivity", "launch"] {
            XCTAssertTrue(names.contains(name), name)
        }
    }

    func testNothingIsRecordedIntoADisabledLog() {
        let nav = DebugNav(log: NoDebugLog(), now: clock.function)
        nav.from(.intent)
        nav.opened(.showerPage, default: .homeButton)
    }
}
