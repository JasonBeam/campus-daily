import Foundation

/// The first-run setup (暖橙's guide, 清爽's checklist) has been seen: it does not open by itself
/// again. Kept in the app's preferences under `key`, which both themes' roots read.
public enum QuickSetupSeen {
    public static let key = "didSeeQuickSetup"

    /// The setup closed. Seen, unless it closed because 「先看看示例」 opened over it
    /// (`coveredBySample`): then nothing is stored, and leaving the sample finds the setup as before.
    public static func closed(in storage: PreferenceStorage, coveredBySample: Bool) {
        guard !coveredBySample else { return }
        storage.set(true, forKey: key)
    }

    /// A new user: the setup was never seen and nothing is set up (no school account, hot water
    /// or laundry). The first-run setup opens by itself only then, and 「选一个样子」 before it.
    public static func isFirstRun(in storage: PreferenceStorage, campusConfigured: Bool, showerConfigured: Bool,
                                  laundryConfigured: Bool) -> Bool {
        storage.object(forKey: key) as? Bool != true && !campusConfigured && !showerConfigured && !laundryConfigured
    }
}
