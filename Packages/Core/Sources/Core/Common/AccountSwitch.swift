import Foundation

/// What the app clears when someone else signs in on this iPhone: the previous person's numbers
/// (the shared snapshot) and their hot-water binding. The binding is never dropped while the
/// shower may still need it (a shower running or not yet settled): then the new person is asked
/// to check the dorm instead, and so too when deleting it failed.
public enum AccountSwitch {
    /// The one-time alert after the clean-up. A confirmed switch says so; a login that couldn't
    /// tell whether it was the previous person says the dorm and meter were cleared to be safe,
    /// but only when they were (the same room keeps them). A removed hot-water binding adds the
    /// same line and button to either; alone, it is the whole alert. nil = nothing to tell.
    public struct Notice: Sendable, Equatable {
        public let title: String
        public let message: String?
        /// The button that opens the hot-water setup; nil = only 「好」.
        public let openHotWater: String?

        static let hotWater = "热水要重新设置。"

        public init?(previousPersonUnconfirmed: Bool, dormAndMeterCleared: Bool, hotWaterCleared: Bool) {
            openHotWater = hotWaterCleared ? "去设置热水" : nil
            if !previousPersonUnconfirmed {
                title = "换了账号，上一个账号的宿舍和电表已经清掉。"
                message = hotWaterCleared ? Self.hotWater : nil
            } else if dormAndMeterCleared {
                title = "认不出是不是之前那个账号，宿舍和电表先清掉了，重新选一下。"
                message = hotWaterCleared ? Self.hotWater : nil
            } else if hotWaterCleared {
                title = Self.hotWater
                message = nil
            } else {
                return nil
            }
        }
    }

    public enum HotWater: Sendable, Equatable {
        /// There was no binding.
        case none
        /// The binding is gone.
        case cleared
        /// Kept (a shower may still need it, or deleting failed): the dorm needs a look.
        case keptForReview
        /// Whether the switch notice mentions hot water.
        public var noticed: Bool { self != .none }
    }

    /// `mayClear`: no shower running or waiting to be settled. `delete` removes the binding.
    public static func clearHotWater(hasBinding: Bool, mayClear: Bool, delete: () throws -> Void) -> HotWater {
        guard hasBinding else { return .none }
        guard mayClear else { return .keptForReview }
        do { try delete() } catch { return .keptForReview }
        return .cleared
    }

    /// The order of the clean-up: the snapshot first (so no screen or widget shows the previous
    /// person's balance), then hot water. A failed snapshot write still goes on to hot water.
    /// Runs in the caller's isolation (the app's main actor), so the closures may touch its models.
    public static func clearPreviousPerson(isolation: isolated (any Actor)? = #isolation,
                                           snapshot: () async throws -> Void, hotWater: () -> HotWater) async -> HotWater {
        try? await snapshot()
        return hotWater()
    }
}
