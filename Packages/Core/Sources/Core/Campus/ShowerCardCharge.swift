import Foundation

/// A shower's charge as the campus card's records show it, for display only. The school books
/// a shower about an hour after it, stamped with the second the shower started; so the one
/// hot-water payment stamped with that second is this shower's. None, or two in that second
/// (they can't be told apart), is no answer. Nothing here changes or settles a shower, and
/// nothing is guessed from balances or the controller.
public enum ShowerCardCharge {
    /// The amount of the one hot-water payment at `started` (to the second, the school's
    /// calendar) in `records`; nil when there is none, more than one, or no records.
    public static func amount(started: Date?, records: [CardRecord]?,
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
