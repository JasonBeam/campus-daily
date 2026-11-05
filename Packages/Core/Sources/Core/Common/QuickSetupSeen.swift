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
}
