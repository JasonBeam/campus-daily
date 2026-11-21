//
//  LaundryOrderPoller.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/16.
//

import Foundation
import Core

/// The scene's order reads while the app is in front (`LaundryForegroundPoll` says when). It
/// runs as a task whose identity is `LaundryModel.pollIdentity`: rebuilt when the app comes to
/// or leaves the front, the engine changes or another order opens, never for the start record
/// or a running step, so a start the read leads to is not cancelled by its own progress.
///
/// A read here is `LaundryModel.refreshOrder`, which may send the pre-start read and
/// `control/start` under the engine's rules.
@MainActor struct LaundryOrderPoller {
    let laundry: LaundryModel
    /// The done reminder will notify (`Reminders.laundryDoneWillNotify`).
    let remindersOn: @MainActor () -> Bool
    var now: @MainActor () -> Date = { Date() }
    /// Waits one tick; throws once the task is cancelled.
    var tick: @Sendable () async throws -> Void = { try await Task.sleep(for:.seconds(1)) }

    func run() async {
        var poll = LaundryForegroundPoll(frontSince:now())
        while !Task.isCancelled {
            if laundry.schoolEnabled, poll.isDue(laundry.checkout, remindersOn:remindersOn(), now:now()) {
                let outcome = await laundry.refreshOrder()
                poll.record(outcome, at:now())
            }
            do { try await tick() } catch { return }
        }
    }
}
