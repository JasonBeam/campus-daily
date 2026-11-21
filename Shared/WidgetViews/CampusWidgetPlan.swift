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
    struct Face {
        let date: Date
        let model: CampusWidgetModel
    }
    struct Faces {
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
