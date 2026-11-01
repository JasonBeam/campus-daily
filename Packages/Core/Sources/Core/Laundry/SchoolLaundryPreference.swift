import Foundation

/// 「学校洗衣机」: whether the dorm uses the school's U净 washers. Off hides laundry everywhere
/// (home, reminders, Live Activity, quick setup) but keeps the U净 login and saved machines, so
/// turning it back on restores everything at once.
///
/// Default on; only an explicit 「不用」 (first-run question or the settings switch) turns it off.
public struct SchoolLaundryPreference {
    public static let key = PreferenceKey.schoolLaundry
    private let storage: any PreferenceStorage

    public init(storage: any PreferenceStorage) { self.storage = storage }

    public var isOn: Bool {
        if let value = storage.object(forKey:Self.key) as? Bool { return value }
        if let number = storage.object(forKey:Self.key) as? NSNumber { return number.boolValue }
        return true
    }

    public func set(_ on: Bool) { storage.set(on, forKey:Self.key) }

    /// First-run 「宿舍用学校的洗衣机吗？」: 用 → on, 不用 → off.
    public func answer(usesSchoolWashers: Bool) { set(usesSchoolWashers) }

    // MARK: Switch rules

    /// Turning it off waits until no laundry order is unfinished (same rule as replacing settings
    /// mid-run: nothing may be in flight). Turning it on is always allowed.
    public static func mayTurnOff(checkout: LaundryPhase?, busy: Bool) -> Bool {
        !busy && (checkout ?? LaundryPhase.none) == LaundryPhase.none
    }

    /// The settings switch is greyed out: on, with an unfinished order.
    public static func switchLocked(isOn: Bool, checkout: LaundryPhase?, busy: Bool) -> Bool {
        isOn && !mayTurnOff(checkout:checkout, busy:busy)
    }

    // MARK: Copy (campus-laundry-optional-copy.md)

    public static let title = "学校洗衣机"
    public static let footerOn = "关掉后，首页和提醒里都不显示洗衣。"
    public static let footerOff = "打开后就能扫码洗衣。"
    public static let footerLocked = "洗衣还有一笔没处理完，处理完再关。"
    /// A laundry shortcut run while it is off.
    public static let offDialog = "学校洗衣机已关掉，去校日常的设置里打开就能用。"

    public static func footer(isOn: Bool, locked: Bool) -> String {
        if locked { return footerLocked }
        return isOn ? footerOn : footerOff
    }

    public enum Onboarding {
        public static let title = "宿舍用学校的洗衣机吗？"
        public static let subtitle = "有的宿舍换成了自己买的洗衣机。不用的话，洗衣就不显示了。"
        public static let yes = "用，接着设置"
        public static let no = "不用"
        public static let note = "以后可以在设置里改。"
    }
}
