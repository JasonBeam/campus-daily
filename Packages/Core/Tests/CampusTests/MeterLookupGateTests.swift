import XCTest
import Core

/// When the automatic meter lookup starts: at launch, after every sign-in and on 「再找一次电表」,
/// only signed in with no meter bound; never by itself in the foreground or after a refresh.
/// What it offered (a same-name list, a stopped level) stays on screen while it runs again.
final class MeterLookupGateTests: XCTestCase {
    static let candidate = MeterCandidate(meter: Meter(comAddress: "000000000991", name: "99栋991"),
                                          path: [MeterWalkTests.campus, MeterWalkTests.apartment, MeterWalkTests.building,
                                                 MeterWalkTests.floor, MeterWalkTests.room])
    static let other = MeterCandidate(meter: Meter(comAddress: "000000000994", name: "99栋991"),
                                      path: [MeterWalkTests.campus, MeterWalkTests.apartment, MeterWalkTests.building,
                                             MeterWalkTests.floor, PowerNode(id: "991001001000109000001004", name: "991")])
    static let stop = MeterWalkStop(level: .floor, path: [MeterWalkTests.campus, MeterWalkTests.apartment, MeterWalkTests.building],
                                    options: [MeterWalkTests.floor])
    static let binding = Harness.roomBinding
    static let apartments = MeterWalkStop(level: .apartment, path: [MeterWalkTests.campus], options: [MeterWalkTests.apartment])

    func testOnlyLaunchASignInOrTheButtonStartIt() {
        XCTAssertEqual(MeterLookupGate.Trigger.allCases, [.launch, .signedIn, .manual], "no foreground or after-refresh start")
        for trigger in MeterLookupGate.Trigger.allCases {
            var gate = MeterLookupGate()
            XCTAssertTrue(gate.start(trigger, signedIn: true, meterBound: false), "\(trigger)")
            XCTAssertTrue(gate.running)
        }
    }

    func testOnlySignedInWithoutAMeter() {
        for trigger in MeterLookupGate.Trigger.allCases {
            var gate = MeterLookupGate()
            XCTAssertFalse(gate.start(trigger, signedIn: false, meterBound: false), "\(trigger)")
            XCTAssertFalse(gate.start(trigger, signedIn: true, meterBound: true), "\(trigger)")
            XCTAssertFalse(gate.running)
        }
    }

    /// Back to back: no wait between lookups (no ten-minute limit any more).
    func testItStartsAgainRightAfterOneEnds() {
        var gate = MeterLookupGate()
        XCTAssertTrue(gate.start(.launch, signedIn: true, meterBound: false))
        _ = gate.ended()
        XCTAssertTrue(gate.start(.manual, signedIn: true, meterBound: false))
        gate.answered(.stopped(Self.stop), stamp: 1)
        XCTAssertTrue(gate.start(.manual, signedIn: true, meterBound: false))
    }

    /// A sign-in while a lookup runs may have brought another dorm: looked for once it ends.
    func testASignInWhileItRunsIsLookedForOnceItEnds() {
        var gate = MeterLookupGate()
        XCTAssertTrue(gate.start(.launch, signedIn: true, meterBound: false))
        XCTAssertFalse(gate.start(.signedIn, signedIn: true, meterBound: false), "not two at once")
        XCTAssertFalse(gate.start(.signedIn, signedIn: true, meterBound: false))
        XCTAssertTrue(gate.ended(), "the sign-in's own lookup is due")
        XCTAssertTrue(gate.start(.signedIn, signedIn: true, meterBound: false))
        XCTAssertFalse(gate.ended(), "asked for once")
    }

    func testTheButtonOrALaunchWhileItRunsAddsNothing() {
        var gate = MeterLookupGate()
        XCTAssertTrue(gate.start(.signedIn, signedIn: true, meterBound: false))
        XCTAssertFalse(gate.start(.manual, signedIn: true, meterBound: false))
        XCTAssertFalse(gate.start(.launch, signedIn: true, meterBound: false))
        gate.answered(.stopped(Self.stop), stamp: 1)
        XCTAssertFalse(gate.ended())
    }

    /// The user is choosing from a same-name list when another lookup starts (a sign-in): the
    /// list stays until that one answers, then its answer replaces it.
    func testAListBeingChosenFromStaysWhileItRunsAgain() {
        var gate = MeterLookupGate()
        _ = gate.start(.launch, signedIn: true, meterBound: false)
        gate.answered(.chooseAmong([Self.candidate, Self.other]), stamp: 4)
        XCTAssertEqual(gate.choices, [Self.candidate, Self.other])
        XCTAssertEqual(gate.choicesStamp, 4)
        XCTAssertTrue(gate.start(.manual, signedIn: true, meterBound: false))
        XCTAssertEqual(gate.choices.count, 2, "not cleared under the user's finger")
        gate.answered(.stopped(Self.stop), stamp: 4)
        XCTAssertEqual(gate.choices, [])
        XCTAssertNil(gate.choicesStamp)
        XCTAssertEqual(gate.stop, Self.stop)
    }

    /// The meter page open at a stopped level while the walk runs again: the level stays.
    func testAStoppedLevelStaysWhileItRunsAgain() {
        var gate = MeterLookupGate()
        _ = gate.start(.launch, signedIn: true, meterBound: false)
        gate.answered(.stopped(Self.stop), stamp: 1)
        _ = gate.start(.manual, signedIn: true, meterBound: false)
        XCTAssertEqual(gate.stop, Self.stop)
        gate.answered(.chooseAmong([Self.candidate, Self.other]), stamp: 1)
        XCTAssertNil(gate.stop)
        XCTAssertEqual(gate.choices.count, 2)
    }

    /// A failed lookup (too slow, offline) or one dropped for another person answers nothing:
    /// what was on screen stays.
    func testAFailureKeepsWhatWasShown() {
        var gate = MeterLookupGate()
        _ = gate.start(.launch, signedIn: true, meterBound: false)
        gate.answered(.stopped(Self.stop), stamp: 1)
        _ = gate.start(.manual, signedIn: true, meterBound: false)
        _ = gate.ended()
        XCTAssertFalse(gate.running)
        XCTAssertEqual(gate.stop, Self.stop)
    }

    func testABoundMeterOrNoDormClearsTheListAndTheStop() {
        for answer in [ElectricityResolution.matched(Self.binding, Meter(comAddress: "000000000991", name: "99栋991")),
                       .alreadyBound(Self.binding), .noAddress] {
            var gate = MeterLookupGate()
            _ = gate.start(.launch, signedIn: true, meterBound: false)
            gate.answered(.chooseAmong([Self.candidate, Self.other]), stamp: 1)
            _ = gate.start(.manual, signedIn: true, meterBound: false)
            gate.answered(answer, stamp: 1)
            XCTAssertFalse(gate.running)
            XCTAssertEqual(gate.choices, [], "\(answer)")
            XCTAssertNil(gate.stop, "\(answer)")
        }
    }

    /// A sign-in, a sign-out or a meter chosen by hand: nothing of the last lookup is shown. A
    /// lookup still running keeps running (it checks the person itself).
    func testClearingDropsTheListAndTheStopOnly() {
        var gate = MeterLookupGate()
        _ = gate.start(.launch, signedIn: true, meterBound: false)
        gate.answered(.stopped(Self.stop), stamp: 1)
        _ = gate.start(.manual, signedIn: true, meterBound: false)
        gate.clear()
        XCTAssertNil(gate.stop)
        XCTAssertEqual(gate.choices, [])
        XCTAssertTrue(gate.running)
    }

    /// A meter picked by hand while the lookup ran: its late list or stop is not shown, and
    /// says it was not (the app then says nothing about it).
    func testALateAnswerAfterAMeterWasBoundIsNotShown() {
        for answer in [ElectricityResolution.stopped(Self.stop), .chooseAmong([Self.candidate, Self.other]), .noAddress] {
            var gate = MeterLookupGate()
            _ = gate.start(.manual, signedIn: true, meterBound: false)
            gate.clear()
            XCTAssertFalse(gate.answered(answer, stamp: 1, meterBound: true), "\(answer)")
            XCTAssertEqual(gate.choices, [])
            XCTAssertNil(gate.choicesStamp)
            XCTAssertNil(gate.stop)
            XCTAssertFalse(gate.running)
        }
        var gate = MeterLookupGate()
        _ = gate.start(.manual, signedIn: true, meterBound: false)
        XCTAssertTrue(gate.answered(.stopped(Self.stop), stamp: 1, meterBound: false))
        XCTAssertEqual(gate.stop, Self.stop)
    }

    /// The meter page opens at the stop only while no meter is bound.
    func testThePageOpensAtTheStopOnlyWithoutAMeter() {
        var gate = MeterLookupGate()
        _ = gate.start(.manual, signedIn: true, meterBound: false)
        gate.answered(.stopped(Self.stop), stamp: 1)
        XCTAssertEqual(gate.pageStop(meterBound: false), Self.stop)
        XCTAssertNil(gate.pageStop(meterBound: true))
        let empty = MeterWalkStop(level: .campus, path: [], options: [])
        gate.answered(.stopped(empty), stamp: 1)
        XCTAssertNil(gate.pageStop(meterBound: false), "nothing to choose from: the page starts at the campuses")
    }

    /// A stop with rooms to bind keeps the stamp of the lookup that found them: a pick after
    /// someone else signed in is refused.
    func testAStopKeepsTheStampOfItsLookup() {
        var gate = MeterLookupGate()
        _ = gate.start(.launch, signedIn: true, meterBound: false)
        gate.answered(.stopped(Self.stop), stamp: 7)
        XCTAssertEqual(gate.stopStamp, 7)
        gate.clear()
        XCTAssertNil(gate.stopStamp)
        gate.answered(.chooseAmong([Self.candidate, Self.other]), stamp: 8)
        XCTAssertNil(gate.stopStamp)
    }

    /// Unfinished at the apartments: nothing to open the page at, and the page shows no list
    /// until a lookup answers otherwise.
    func testAnUnfinishedLookupHidesTheList() {
        var gate = MeterLookupGate()
        _ = gate.start(.launch, signedIn: true, meterBound: false)
        gate.answered(.stopped(Self.stop), stamp: 1)
        _ = gate.ended()
        _ = gate.start(.manual, signedIn: true, meterBound: false)
        gate.answered(.unfinished(Self.apartments), stamp: 1)
        XCTAssertEqual(gate.unfinished, Self.apartments)
        XCTAssertNil(gate.stop)
        XCTAssertNil(gate.pageStop(meterBound: false))
        _ = gate.start(.manual, signedIn: true, meterBound: false)
        XCTAssertEqual(gate.unfinished, Self.apartments, "stays while it runs again")
        gate.answered(.stopped(Self.stop), stamp: 1)
        XCTAssertNil(gate.unfinished)
        gate.answered(.unfinished(Self.apartments), stamp: 1)
        gate.clear()
        XCTAssertNil(gate.unfinished)
    }
}
