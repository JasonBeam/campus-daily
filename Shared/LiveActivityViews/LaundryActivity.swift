import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity for one paid, running laundry order. Compiled into both the app and the widget.
/// Read only: there is no button, laundry ends by itself.
struct LaundryActivityAttributes: ActivityAttributes {
    enum Phase: String, Codable, Hashable { case running, done }
    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// Drives the progress line (`ProgressView(timerInterval:)`), so it moves without updates.
        /// The order has no start time; this is end − program length (or the order's creation).
        var startedAt: Date
        /// Expected end, from the order's remaining time at the last read.
        var endsAt: Date
        /// Whole minutes left at the last read; updated by the app on each order re-read / foreground.
        var minutesLeft: Int
    }
    /// U净 order id, to match later reads to this activity.
    var orderId: String
    /// e.g. "3 号机".
    var machine: String
    /// e.g. "标准洗".
    var program: String
}
#endif
