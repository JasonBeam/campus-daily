//
//  SingleFlight.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import Foundation

/// One run of a piece of work at a time on the main actor: a call while a run is in flight
/// starts nothing and waits for that run instead. For work started on every return to the
/// foreground (`CampusModel.finishPendingClear`), so a run that is slow to end can't pile up
/// more of them behind it.
@MainActor public final class SingleFlight {
    private var running: Task<Void, Never>?
    /// How many runs were started (tests).
    public private(set) var started = 0

    public init() {}

    /// Runs `work`, or waits for the run already in flight. True when this call started the run.
    @discardableResult
    public func run(_ work: @escaping @Sendable () async -> Void) async -> Bool {
        if let running {
            await running.value
            return false
        }
        started += 1
        let task = Task.detached(priority: .userInitiated) { await work() }
        running = task
        await task.value
        running = nil
        return true
    }
}
