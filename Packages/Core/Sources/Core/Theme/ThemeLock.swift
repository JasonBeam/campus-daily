import Foundation

/// Why the theme options are greyed out: a shower or laundry run is going on, and the screens
/// that follow it must not change look halfway through. The settings row stays open.
public enum ThemeLock: Sendable, Equatable {
    case shower
    case laundry
    case showerAndLaundry

    /// Shower: from 开始洗澡 (connecting to the controller and authorizing, before any water)
    /// until the settlement is done. A record waiting to be checked (结算待核对 and the like) does not
    /// count: nothing is running then. Laundry: while an order is unfinished — being created or
    /// looked for, unpaid, being paid or verified, running, or being cancelled. An order the
    /// machine didn't start (kept for the user to acknowledge) is over and does not count.
    public static func lock(shower: ShowerState?, laundry: LaundryPhase?) -> ThemeLock? {
        switch (showerRuns(shower), laundryOpen(laundry)) {
        case (true, true): return .showerAndLaundry
        case (true, false): return .shower
        case (false, true): return .laundry
        case (false, false): return nil
        }
    }

    public static func showerRuns(_ shower: ShowerState?) -> Bool {
        switch shower?.phase {
        case .authorizing?, .writePending?, .running?, .closing?, .settling?: return true
        case .idle?, .done?, .failed?, nil: return false
        }
    }

    public static func laundryOpen(_ phase: LaundryPhase?) -> Bool {
        switch phase {
        case .creating?, .reconcile?, .created?, .paying?, .verifying?, .active?, .cancelling?: return true
        case LaundryPhase.none?, .attention?, nil: return false
        }
    }

    /// The footer's first line while greyed out.
    public var reason: String {
        switch self {
        case .shower: return "正在洗澡，结算以后再换主题。"
        case .laundry: return "洗衣还有一笔订单没处理完，处理完再换主题。"
        case .showerAndLaundry: return "先结算热水、处理完洗衣订单，再换主题。"
        }
    }
}
