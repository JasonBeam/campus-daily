import Foundation

/// When Settings may replace the dorm binding or the hot-water platform profile.
public enum ShowerImportRule {
    /// Binding and profile: only with no session that could still be open or charged.
    public static func mayImport(_ state: ShowerState, busy: Bool, storageBlocked: Bool) -> Bool {
        !busy && !storageBlocked
            && (state.phase == .idle || state.phase == .done || (state.phase == .failed && state.failure?.needsReview == false))
    }

    /// The profile alone: also while a shower waits on a missing one (there is nothing to
    /// replace; it is what 结束 and 再结算一次 need), but only once the profile load at launch
    /// has finished. Before that a profile only looks missing, and an import could overwrite
    /// the one this session uses.
    public static func mayImportProfile(_ state: ShowerState, profileLoaded: Bool, profileMissing: Bool,
                                        busy: Bool, storageBlocked: Bool) -> Bool {
        mayImport(state, busy: busy, storageBlocked: storageBlocked)
            || (profileLoaded && profileMissing && !busy && !storageBlocked)
    }
}
