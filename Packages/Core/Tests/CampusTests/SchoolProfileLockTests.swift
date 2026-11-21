//
//  SchoolProfileLockTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core
import CoreTestSupport

/// The stored profile is shared with the widget, whose refresh moves the meter's address in a
/// locked step. Every change the app makes to it is one read-compare-write inside the same
/// lock, so neither lands in the middle of the other.
final class SchoolProfileLockTests: XCTestCase {
    final class Lock: SharedLock, @unchecked Sendable {
        private let state = NSLock()
        private var depth = 0
        private var step: (@Sendable () -> Void)?
        var held: Bool { state.withLock { depth > 0 } }
        /// What the other process does last before this lock is next taken.
        func beforeTaken(_ step: @escaping @Sendable () -> Void) { state.withLock { self.step = step } }
        func locked<T>(_ body: () throws -> T) throws -> T {
            state.withLock { let s = step; step = nil; return s }?()
            state.withLock { depth += 1 }
            defer { state.withLock { depth -= 1 } }
            return try body()
        }
    }

    static let meter = Meter(comAddress: "000000000991", name: "99栋991")

    func harness() -> (Harness, Lock) {
        var h = Harness()
        let lock = Lock()
        h.profileLock = lock
        return (h, lock)
    }

    /// The next profile write (call after the set-up's own) must find the lock held.
    func lockedWrite(_ h: Harness, _ lock: Lock) -> XCTestExpectation {
        let wrote = expectation(description: "profile written")
        h.store.beforeNextWrite(to: .schoolProfile) {
            XCTAssertTrue(lock.held, "written outside the lock")
            wrote.fulfill()
        }
        return wrote
    }

    func testTheMatchedMeterIsWrittenInsideTheLock() async throws {
        let (h, lock) = harness()
        try h.signedIn()
        try SchoolElectricityTests.serveTree(h)
        let wrote = lockedWrite(h, lock)
        guard case .matched = try await h.session().resolveElectricity() else { return XCTFail("not matched") }
        await fulfillment(of: [wrote], timeout: 1)
    }

    /// The dorm read from the portal goes onto the profile as it is inside the lock: a meter
    /// address the widget moved just before stays moved.
    func testTheDormIsWrittenOntoTheProfileReadInsideTheLock() async throws {
        let (h, lock) = harness()
        try h.vault.saveEcyktSession(T.session())
        try h.vault.savePortalToken(PortalToken("PORTAL"))
        try h.vault.saveProfile(SchoolProfile(residence: nil, meter: MeterBinding(
            nodeID: MeterWalkTests.room.id, comAddress: "000000000991", label: "99栋 991", nodeIsRoom: true)))
        try h.server.serve("portal/getMyInfo-ok")
        try SchoolElectricityTests.serveTree(h)
        let vault = h.vault
        lock.beforeTaken {
            guard var moved = try? vault.profile() else { return }
            moved.meter?.comAddress = "000000000992"
            try? vault.saveProfile(moved)
        }
        guard case .alreadyBound = try await h.session().resolveElectricity() else { return XCTFail("not bound") }
        XCTAssertNotNil(try h.vault.profile()?.residence?.address)
        XCTAssertEqual(try h.vault.profile()?.meter?.comAddress, "000000000992")
    }

    func testAPickedMeterIsWrittenInsideTheLock() async throws {
        let (h, lock) = harness()
        try h.signedIn()
        let wrote = lockedWrite(h, lock), session = h.session()
        try await session.chooseMeter(nodeID: MeterWalkTests.room.id, meter: Self.meter, since: await session.personStamp())
        await fulfillment(of: [wrote], timeout: 1)
        XCTAssertEqual(try h.vault.profile()?.meter?.comAddress, "000000000991")
    }

    func testAChoiceAmongSameNameRoomsIsWrittenInsideTheLock() async throws {
        let (h, lock) = harness()
        try h.signedIn()
        let wrote = lockedWrite(h, lock), session = h.session()
        let candidate = MeterCandidate(meter: Self.meter, path: [MeterWalkTests.campus, MeterWalkTests.building, MeterWalkTests.room])
        try await session.chooseMatchedMeter(candidate, since: await session.personStamp())
        await fulfillment(of: [wrote], timeout: 1)
        XCTAssertEqual(try h.vault.profile()?.meter?.nodeID, MeterWalkTests.room.id)
    }

    func testTheCampusWideMeterIsDroppedInsideTheLock() async throws {
        let (h, lock) = harness()
        try h.signedIn(meter: MeterBinding(nodeID: MeterWalkTests.campus.id, comAddress: "000000000991", label: "99栋991", nodeIsRoom: false))
        let wrote = lockedWrite(h, lock)
        let dropped = try await h.session().dropCampusWideMeter()
        XCTAssertTrue(dropped)
        await fulfillment(of: [wrote], timeout: 1)
        XCTAssertNil(try h.vault.profile()?.meter)
    }
}
