//
//  SingleFlightTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
@testable import Core

/// `CampusModel.finishPendingClear` on every return to the foreground: while one run is stuck
/// (waiting for the lease file's lock), more calls start nothing and wait for it.
@MainActor
final class SingleFlightTests: XCTestCase {
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = false, entered = 0
        var runs: Int { lock.withLock { entered } }
        func enter() { lock.withLock { entered += 1 } }
        func release() { lock.withLock { open = true } }
        var isOpen: Bool { lock.withLock { open } }
    }

    func testCallsWhileARunIsBlockedDoNotPileUp() async throws {
        let flight = SingleFlight(), gate = Gate()
        let work: @Sendable () async -> Void = {
            gate.enter()
            while !gate.isOpen { try? await Task.sleep(for: .milliseconds(5)) }
        }
        let first = Task { await flight.run(work) }
        while gate.runs == 0 { try await Task.sleep(for: .milliseconds(5)) }
        let more = (0..<20).map { _ in Task { await flight.run(work) } }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(gate.runs, 1, "one run, however many calls")
        XCTAssertEqual(flight.started, 1)

        gate.release()
        let firstStarted = await first.value
        var othersStarted = 0
        for call in more { if await call.value { othersStarted += 1 } }
        XCTAssertTrue(firstStarted)
        XCTAssertEqual(othersStarted, 0, "the later calls waited for the first run")
        XCTAssertEqual(gate.runs, 1)

        let again = await flight.run(work)
        XCTAssertTrue(again, "a call after the run ended starts a new one")
        XCTAssertEqual(gate.runs, 2)
    }
}
