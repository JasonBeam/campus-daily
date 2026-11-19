import Foundation

/// Where the common-washer page goes once a machine is saved or switched.
public enum WasherSetupExit {
    /// A home stack after the save: the page goes; opened from home itself (the unbound 洗衣
    /// row) the laundry page is pushed over it, so the user lands where the machine is used.
    /// Not swapped in its place: a stack changes its top page for another without a transition.
    /// Unchanged when the page is not on top.
    public static func path<Route: Equatable>(_ path: [Route], setup: Route, laundry: Route) -> [Route] {
        guard path.last == setup else { return path }
        let below = Array(path.dropLast())
        return below.isEmpty ? path + [laundry] : below
    }

    /// The first-run step finishes on every save, the same machine saved again included: the
    /// list does not grow then, the save count does.
    public static func finishesSetupStep(savedAt count: Int, lastSeen: Int) -> Bool { count > lastSeen }
}
