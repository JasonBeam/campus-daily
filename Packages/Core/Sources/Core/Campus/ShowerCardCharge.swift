//
//  ShowerCardCharge.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import Foundation

/// A shower's charge as the campus card's records show it, for display only. The school books
/// a shower about an hour after it, stamped with the second the shower started; so the one
/// hot-water payment stamped with that second is this shower's. None, or two in that second
/// (they can't be told apart), is no answer. Nothing here changes or settles a shower, and
/// nothing is guessed from balances or the controller.
public enum ShowerCardCharge {
    /// As `amount(started:records:)`, from home's read of the recent records, and only when that
    /// read holds every record of the shower's day (`CardActivity.holdsAll`). The school pages
    /// by count, newest first: on a page cut inside that day, a second payment of the same second
    /// may be on the next page, so nothing is shown.
    public static func amount(started: Date?, activity: CardActivity?,
                              calendar: Calendar = SchoolCalendar.shanghai) -> Money? {
        guard let started, let activity,
              activity.holdsAll(of: SchoolCalendar.dayString(started, calendar: calendar)) else { return nil }
        return amount(started: started, records: activity.records, calendar: calendar)
    }

    /// The amount of the one hot-water payment at `started` (to the second, the school's
    /// calendar) in `records`; nil when there is none, more than one, or no records. `records`
    /// must hold every record of that second.
    static func amount(started: Date?, records: [CardRecord]?,
                              calendar: Calendar = SchoolCalendar.shanghai) -> Money? {
        guard let started, let records else { return nil }
        let second = started.timeIntervalSince1970.rounded(.down)
        let matches = records.filter { record in
            record.kind == .shower && record.flow == .moneyOut
                && record.moment(calendar: calendar)?.timeIntervalSince1970 == second
        }
        guard matches.count == 1 else { return nil }
        return matches[0].amount
    }
}
