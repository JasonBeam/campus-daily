//
//  CampusWidgetPlan.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import Foundation
import Core

/// What the widget's provider draws from `WidgetDrawChoice`: the faces of a timeline and when
/// to ask again. A read that could not be done draws the grey bars (no one's numbers, not the
/// signed-out face) and asks again soon; nothing the process drew before stands in for it. A
/// timeline always has a face: an empty one could leave what is on screen as it is.
enum CampusWidgetPlan {
    struct Face: Sendable {
        let date: Date
        let model: CampusWidgetModel
    }
    struct Faces: Sendable {
        let faces: [Face]
        let next: Date
    }

    /// The face for `choice` at `now` (`getSnapshot`, and the first face of a timeline).
    /// `preview`: the gallery, where nobody signed in shows the grey bars too.
    static func face(_ choice: WidgetDrawChoice, now: Date, preview: Bool = false, lines: ReminderLines) -> CampusWidgetModel {
        guard case .draw(let snapshot, let account) = choice else { return noNumbers(now:now) }
        let model = model(snapshot, account:account, at:now, lines:lines)
        return preview && model.state == .never ? noNumbers(now:now) : model
    }

    /// `drawn`: the snapshot the widget's refresh returned after `choice` was read (only
    /// used to draw). Fresh numbers that turn stale with time alone before the next timeline
    /// get a second face at that moment.
    static func timeline(_ choice: WidgetDrawChoice, drawn: HomeSnapshot?, now: Date, interval: TimeInterval,
                         lines: ReminderLines) -> Faces {
        let account: SchoolAccount?
        switch choice {
        case .noNumbers(let retry):
            return Faces(faces:[Face(date:now, model:noNumbers(now:now))], next:now.addingTimeInterval(retry))
        case .draw(_, let stored):
            account = stored
        }
        let next = now.addingTimeInterval(interval)
        var faces = [Face(date:now, model:model(drawn, account:account, at:now, lines:lines))]
        if let staleAt = WidgetStatus.staleAt(snapshot:drawn, account:account, now:now), staleAt < next {
            faces.append(Face(date:staleAt, model:model(drawn, account:account, at:staleAt, lines:lines)))
        }
        return Faces(faces:faces, next:next)
    }

    private static func model(_ snapshot: HomeSnapshot?, account: SchoolAccount?, at date: Date, lines: ReminderLines) -> CampusWidgetModel {
        var model = CampusWidgetModel(snapshot:snapshot, account:account, now:date)
        model.lines = lines
        return model
    }

    private static func noNumbers(now: Date) -> CampusWidgetModel {
        var model = CampusWidgetModel.placeholderFace
        model.now = now
        return model
    }
}

/// Shared delivery boundary for both WidgetKit provider entry points (`getSnapshot` and
/// `getTimeline`). Constructs the candidate face/timeline first (including reading reminder lines),
/// then acquires the shared commit lock immediately before invoking `completion` to verify
/// `shared.sessionEpoch`. If the epoch changed, is not active, or the commit lock is unavailable,
/// discards the candidate and delivers a safe face/timeline (offline-rebuilt or placeholder).
enum CampusWidgetDelivery {
    /// `getSnapshot` delivery path: no network; constructs face first, then verifies under
    /// `commitLock` right before calling `completion`.
    static func deliverSnapshot(
        now: Date,
        preview: Bool,
        snapshots: SnapshotStoring,
        vault: SchoolVault,
        commitLock: any SharedLock,
        lines: () -> ReminderLines,
        beforeVerify: (() -> Void)? = nil,
        completion: (CampusWidgetModel) -> Void
    ) {
        let stored = WidgetStoredData.read(snapshots:snapshots, vault:vault)
        let initial = WidgetDrawChoice.choose(stored)
        let candidateSnapshot: HomeSnapshot? = if case .draw(let snapshot, _) = initial { snapshot } else { nil }
        let reminderLines = lines()
        let constructed = CampusWidgetPlan.face(initial, now:now, preview:preview, lines:reminderLines)
        beforeVerify?()

        let finalModel: CampusWidgetModel
        do {
            finalModel = try commitLock.locked {
                let verified = WidgetDrawChoice.verifiedForCompletion(
                    initial:initial, initialEpoch:stored?.epoch, drawn:candidateSnapshot,
                    snapshots:snapshots, vault:vault
                )
                if verified.choice == initial && verified.drawn == candidateSnapshot {
                    return constructed
                }
                return CampusWidgetPlan.face(verified.choice, now:now, preview:preview, lines:reminderLines)
            }
        } catch {
            // Commit lock unavailable: fail closed with no numbers.
            finalModel = CampusWidgetPlan.face(.noNumbers(retryAfter:WidgetStoredData.unreadableRetry),
                                               now:now, preview:preview, lines:reminderLines)
        }
        completion(finalModel)
    }

    /// `getTimeline` delivery path: finishes pending clear, runs optional network refresh,
    /// reads reminder lines and constructs the candidate timeline FIRST, then verifies under
    /// `commitLock` immediately before calling `completion`.
    static func deliverTimeline(
        now: Date,
        interval: TimeInterval,
        snapshots: SnapshotStoring,
        vault: SchoolVault,
        commitLock: any SharedLock,
        lines: @Sendable () -> ReminderLines,
        finishPendingClear: @Sendable () async -> Void,
        refresh: @Sendable (_ expectedEpochID: String?) async -> HomeSnapshot?,
        beforeVerify: (@Sendable () async -> Void)? = nil,
        completion: @Sendable (CampusWidgetPlan.Faces) -> Void
    ) async {
        await finishPendingClear()
        let stored = WidgetStoredData.read(snapshots:snapshots, vault:vault)
        let initial = WidgetDrawChoice.choose(stored)
        var drawn: HomeSnapshot?
        if case .draw = initial {
            let canRefresh = stored?.epoch?.allowsRefreshCommit ?? true
            if canRefresh {
                drawn = await refresh(stored?.epoch?.id)
            }
        }
        let reminderLines = lines()
        let constructed = CampusWidgetPlan.timeline(initial, drawn:drawn, now:now, interval:interval, lines:reminderLines)
        if let beforeVerify { await beforeVerify() }

        let finalPlan: CampusWidgetPlan.Faces
        do {
            finalPlan = try await commitLock.lockedWhenFree {
                let verified = WidgetDrawChoice.verifiedForCompletion(
                    initial:initial, initialEpoch:stored?.epoch, drawn:drawn,
                    snapshots:snapshots, vault:vault
                )
                if verified.choice == initial && verified.drawn == drawn {
                    return constructed
                }
                return CampusWidgetPlan.timeline(verified.choice, drawn:verified.drawn, now:now,
                                                 interval:interval, lines:reminderLines)
            }
        } catch {
            // Commit lock unavailable: fail closed with one no-numbers entry.
            finalPlan = CampusWidgetPlan.timeline(.noNumbers(retryAfter:WidgetStoredData.unreadableRetry),
                                                  drawn:nil, now:now, interval:interval, lines:reminderLines)
        }
        completion(finalPlan)
    }
}
