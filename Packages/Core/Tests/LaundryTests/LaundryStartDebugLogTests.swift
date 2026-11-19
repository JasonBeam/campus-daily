import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// The TestFlight log over a 立刻洗衣 order: the choice, the Alipay jump, the return, the
/// pre-start read (paid, status, price check), the start (saved, handed over, result) and every
/// reason it was not sent. Fixed words, numbers and a salted order tag only.
final class LaundryStartDebugLogTests: XCTestCase {
    var store: InMemorySecureStore!
    var vault: StoredLaundryVault!
    var api: FakeLaundryAPI!
    var launcher: FakeLauncher!
    var front: FrontSwitch!
    var clock: TestClock!
    var folder: URL!

    static let account = "acct-1"

    override func setUp() { reset() }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func reset() {
        store = InMemorySecureStore()
        vault = StoredLaundryVault(store: store)
        api = FakeLaundryAPI()
        launcher = FakeLauncher()
        front = FrontSwitch(true)
        clock = TestClock(L.t0.addingTimeInterval(10))
        folder = DebugLogTesting.temporaryDirectory()
    }

    let paymentURL = "alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url="
        + "https%3A%2F%2Fopenauth.alipay.com%2Foauth2%2FpublicAppAuthorize.htm%3Fredirect_uri%3Dhttps%253A%252F%252Fwx.zhinengxiyifang.cn%252Fstatic%252FcommonWasher%252Findex.html"

    var secrets: [String] {
        [L.orderID, L.device, L.qr, "000000000000000001", L.token, L.mobileID, Self.account, "alipays", "openauth", "20000042",
         "测试洗衣机01", "示例洗衣房", "test-store-01", "标准洗", "设备未关门"]
    }

    func engine(_ log: any DebugLogSink, account: String? = LaundryStartDebugLogTests.account) throws -> LaundryEngine {
        let front = self.front!, clock = self.clock!
        return try LaundryEngine(api: api, vault: vault, launcher: launcher, accountID: account,
                                 inFront: { front.value }, now: { clock.now }, sleep: { _ in }, debugLog: log)
    }

    /// Confirmed as 立刻洗衣 and handed to Alipay.
    func paying(_ log: any DebugLogSink) async throws -> LaundryEngine {
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        api.methods = [.ok([PayChannel(channel: "alipayF2F", branchType: 0)])]
        api.arguments = [.ok(PaymentArguments(.object(["url": .string(paymentURL)])))]
        let e = try engine(log)
        _ = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard, immediate: true)
        _ = try await e.pay()
        return e
    }

    func assertInOrder(_ expected: [String], _ lines: [String], file: StaticString = #filePath, line: UInt = #line) {
        var i = 0
        for want in expected {
            while i < lines.count, lines[i] != want { i += 1 }
            guard i < lines.count else {
                return XCTFail("missing or out of order: \(want)\n" + lines.joined(separator: "\n"), file: file, line: line)
            }
            i += 1
        }
    }

    /// A whole 立刻洗衣 order through the real file log: every step, in order, and no value.
    func testAFullImmediateOrderLeavesEveryStepAndNoValue() async throws {
        let log = FileDebugLog(directory: FileDebugLog.directory(in: folder), now: { L.t0 }, timeZone: TimeZone(identifier: "UTC")!)
        let e = try await paying(log)
        api.orders = [.ok(L.order("20")), .ok(L.order("40", remain: 1800))]
        api.startChecks = [.ok(L.check())]
        api.starts = [.ok(true)]
        let s = try await e.returnedFromPayment()
        XCTAssertEqual(s.start, .started)

        let o = log.tag(DebugTag(.order, L.orderID))
        let bodies = log.lines().map { String($0.dropFirst(15)) }
        assertInOrder([
            "laundry.start chosen immediate=yes",
            "laundry.request create ok",
            "laundry.request paymentArguments ok",
            "laundry.payLaunch opened=yes",
            "laundry.start returned inFront=yes",
            "laundry.order status=20 order=\(o)",
            "laundry.request startCheck ok",
            "laundry.start check paid=yes status=20 price=ok moduleType=7 order=\(o)",
            "laundry.start saved",
            "laundry.start handed",
            "laundry.request startWasher ok",
            "laundry.start result=ok",
            "laundry.order status=40 order=\(o)",
        ], bodies)
        XCTAssertEqual(bodies.filter { $0 == "laundry.start handed" }.count, 1)
        let all = bodies.joined(separator: "\n") + (try String(contentsOf: log.eventsFile, encoding: .utf8))
        XCTAssertEqual(DebugLogTesting.leaks(secrets, in: all), [])
        XCTAssertEqual(log.droppedCount, 0)
    }

    /// A normal order says so at the choice and has no start lines after it.
    func testANormalOrderHasNoStartLines() async throws {
        let log = RecordingDebugLog()
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        let e = try engine(log)
        _ = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard)
        XCTAssertTrue(log.lines().contains("laundry.start chosen immediate=no"), log.lines().joined(separator: "\n"))
        XCTAssertEqual(log.lines().filter { $0.hasPrefix("laundry.start ") && $0 != "laundry.start chosen immediate=no" }, [])
    }

    func testBackInTheBackgroundIsSkippedAsNotInFront() async throws {
        let log = RecordingDebugLog()
        let e = try await paying(log)
        front.value = false
        api.orders = [.ok(L.order("20"))]
        _ = try await e.returnedFromPayment()
        assertInOrder(["laundry.start returned inFront=no", "laundry.start skipped reason=notFront"], log.lines())
        XCTAssertFalse(log.lines().contains("laundry.start handed"))
    }

    func testPastTenMinutesIsSkippedAsExpired() async throws {
        let log = RecordingDebugLog()
        let e = try await paying(log)
        clock.now = L.t0.addingTimeInterval(10 + 601)
        api.orders = [.ok(L.order("20"))]
        _ = try await e.returnedFromPayment()
        XCTAssertTrue(log.lines().contains("laundry.start skipped reason=expired"), log.lines().joined(separator: "\n"))
        XCTAssertFalse(log.lines().contains("laundry.start handed"))
    }

    func testAnotherAccountIsSkippedAsAccount() async throws {
        let log = RecordingDebugLog()
        let e = try await paying(log)
        // Same engine, other account: rebuild it as the app does after a switch.
        _ = e
        let other = try engine(log, account: "acct-2")
        api.orders = [.ok(L.order("20"))]
        _ = try await other.refresh()
        XCTAssertTrue(log.lines().contains("laundry.start skipped reason=account"), log.lines().joined(separator: "\n"))
        XCTAssertFalse(log.lines().contains("laundry.start handed"))
        XCTAssertEqual(DebugLogTesting.leaks(secrets + ["acct-2"], in: log.lines().joined()), [])
    }

    func testMachinesLeftToUjingAreSkippedWithTheirReason() async throws {
        let checks: [(LaundryStartCheck, String)] = [
            (L.check(module: 1), "laundry.start skipped reason=unsupported"),
            (L.check(online: false), "laundry.start skipped reason=offline"),
            (L.check(selfClean: true), "laundry.start skipped reason=selfClean"),
            (L.check(dispenser: true), "laundry.start skipped reason=dispenser"),
        ]
        for (check, want) in checks {
            reset()
            let log = RecordingDebugLog()
            let e = try await paying(log)
            api.orders = [.ok(L.order("20"))]
            api.startChecks = [.ok(check)]
            _ = try await e.returnedFromPayment()
            XCTAssertTrue(log.lines().contains(want), want + "\n" + log.lines().joined(separator: "\n"))
            XCTAssertFalse(log.lines().contains("laundry.start handed"))
        }
    }

    func testThePriceCheckIsLoggedOkMismatchOrUnreadable() async throws {
        let checks: [(LaundryStartCheck, [String])] = [
            (L.check(price: 401), ["laundry.start check paid=yes status=20 price=mismatch moduleType=7 order=o:tag",
                                   "laundry.start skipped reason=price"]),
            (L.check(price: nil), ["laundry.start check paid=yes status=20 price=unreadable moduleType=7 order=o:tag",
                                   "laundry.start skipped reason=price"]),
            (L.check(paid: false), ["laundry.start check paid=no status=20 price=ok moduleType=7 order=o:tag",
                                    "laundry.start skipped reason=status"]),
            (L.check(id: "OTHERORDER0002"), ["laundry.start skipped reason=otherOrder"]),
        ]
        for (check, want) in checks {
            reset()
            let log = RecordingDebugLog()
            let e = try await paying(log)
            api.orders = [.ok(L.order("20"))]
            api.startChecks = [.ok(check)]
            _ = try await e.returnedFromPayment()
            assertInOrder(want, log.lines())
            XCTAssertEqual(log.lines().filter { $0.hasPrefix("laundry.start skipped") }.count, 1, log.lines().joined(separator: "\n"))
            XCTAssertFalse(log.lines().contains("laundry.start handed"))
            XCTAssertEqual(DebugLogTesting.leaks(secrets + ["OTHERORDER0002"], in: log.lines().joined()), [])
        }
    }

    /// U净's refusal keeps its code, never its sentence; an unclear reply is `unknown` with its kind.
    func testStartResultsRefusedAndUnknown() async throws {
        let outcomes: [(FakeLaundryAPI.Outcome<Bool>, String)] = [
            (.fail(.rejected(.ujing, code: "errorMessage", message: "设备未关门")), "laundry.start result=refused code=errorMessage"),
            (.fail(.timedOut), "laundry.start result=unknown kind=uncertain"),
            (.fail(.offline), "laundry.start result=unknown kind=uncertain"),
        ]
        for (outcome, want) in outcomes {
            reset()
            let log = RecordingDebugLog()
            let e = try await paying(log)
            api.orders = Array(repeating: .ok(L.order("20")), count: 7)
            api.startChecks = [.ok(L.check())]
            api.starts = [outcome]
            _ = try await e.returnedFromPayment()
            assertInOrder(["laundry.start saved", "laundry.start handed", want], log.lines())
            XCTAssertEqual(DebugLogTesting.leaks(secrets, in: log.lines().joined()), [])
        }
    }

    /// The saved-as-sent record could not be written: nothing handed over, and the log says why.
    func testAStartThatCouldNotBeSavedIsSkippedAsNotSaved() async throws {
        let log = RecordingDebugLog()
        let flaky = FlakyLaundryVault(inner: vault) { c in
            if case .sent? = c?.start { return true }
            return false
        }
        api.creates = [.ok(L.orderID)]
        api.orders = [.ok(L.order("10"))]
        api.methods = [.ok([PayChannel(channel: "alipayF2F", branchType: 0)])]
        api.arguments = [.ok(PaymentArguments(.object(["url": .string(paymentURL)])))]
        let front = self.front!, clock = self.clock!
        let e = try LaundryEngine(api: api, vault: flaky, launcher: launcher, accountID: Self.account,
                                  inFront: { front.value }, now: { clock.now }, sleep: { _ in }, debugLog: log)
        _ = try await e.confirmOrder(L.snapshot(at: L.t0.addingTimeInterval(5)), program: L.standard, immediate: true)
        _ = try await e.pay()
        api.orders = [.ok(L.order("20"))]
        api.startChecks = [.ok(L.check())]
        _ = try? await e.returnedFromPayment()
        XCTAssertTrue(log.lines().contains("laundry.start skipped reason=notSaved"), log.lines().joined(separator: "\n"))
        XCTAssertFalse(log.lines().contains("laundry.start saved"))
        XCTAssertFalse(log.lines().contains("laundry.start handed"))
    }

    func testEveryStartLineReadsAsFixedWords() {
        let tag: (DebugTag) -> String = { "\($0.kind.rawValue):tag" }
        let cases: [(DebugLaundryStart, String)] = [
            (.chosen(immediate: true), "chosen immediate=yes"),
            (.returned(inFront: false), "returned inFront=no"),
            (.check(paid: true, status: DebugCode("20"), price: .ok, moduleType: nil, order: nil), "check paid=yes status=20 price=ok"),
            (.saved, "saved"),
            (.handed, "handed"),
            (.result(.ok), "result=ok"),
            (.result(.refused(nil)), "result=refused"),
            (.result(.unknown(.timedOut)), "result=unknown kind=timedOut"),
            (.skipped(.cancelled), "skipped reason=cancelled"),
        ]
        for (step, want) in cases {
            let e = DebugEvent.laundryStart(step)
            XCTAssertEqual(e.name, "laundry.start")
            XCTAssertEqual(e.fields(tag: tag), want)
        }
    }
}
