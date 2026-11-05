import SwiftUI
import Observation
import Core

/// The theme the app draws with. Each model graph owns one (`CampusGraph`) and injects it into
/// the environment; `CampusRootView` hands its theme down as `\.appTheme`, which the tokens resolve
/// from. Observable: the pages are drawn again when the theme changes, so a switch shows at once,
/// without a restart. Written on the main actor only (`select`, `reload`). Stored in the
/// preferences it is given: the App Group's for the live app (where the widget and the Live
/// Activities read it), the sample's own in-memory ones in 「先看看示例」.
@Observable final class ThemeStore: @unchecked Sendable {
    /// What is stored, the theme shown.
    private(set) var stored: AppTheme
    @ObservationIgnored private let preference: ThemePreference
    /// The App Group's lock, which the widget and Live Activities' processes respect.
    @ObservationIgnored private let lock: any SharedLock
    /// Why the theme can't change now (a shower or laundry run going on); nil when it can.
    @ObservationIgnored private let themeLock: @MainActor () -> ThemeLock?
    /// The choice was stored: the widget draws again (nothing for a sample's).
    @ObservationIgnored private let didChange: @Sendable () -> Void

    @MainActor init(preference: ThemePreference, lock: any SharedLock, didChange: @escaping @Sendable () -> Void,
                    themeLock: @escaping @MainActor () -> ThemeLock?) {
        self.preference = preference
        self.lock = lock
        self.didChange = didChange
        self.themeLock = themeLock
        stored = preference.theme
    }

    @MainActor var theme: AppTheme { stored }

    /// Saves the choice where the widget and the Live Activities read it, and has the widget
    /// draw again. Nothing changes while a run locks the theme (`ThemeLock`, whoever asks; 主题
    /// greys its options out too), or when the shared lock can't be taken (the container locked
    /// before the first unlock): the option stays unselected.
    @MainActor func select(_ theme: AppTheme) {
        do {
            guard try preference.select(theme, current:stored, lock:themeLock(), under:lock) else { return }
        } catch { return }
        stored = theme
        didChange()
    }

    /// After 重置校日常 cleared the stored choice: back to what is stored (暖橙).
    @MainActor func reload() {
        let value = preference.theme
        if value != stored { stored = value }
    }
}
