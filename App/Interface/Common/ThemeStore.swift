import SwiftUI
import Observation
import WidgetKit
import Core

/// The theme the app draws with. The app owns one (`XiaoRiChangApp`) and injects it into the
/// environment; `CampusRootView` hands its theme down as `\.appTheme`, which the tokens resolve
/// from. Observable: the pages are drawn again when the theme changes, so a switch shows at once,
/// without a restart. Written on the main actor only (`select`, `reload`).
@Observable final class ThemeStore: @unchecked Sendable {
    private(set) var theme: AppTheme
    @ObservationIgnored private let preference: ThemePreference
    /// The App Group's lock, which the widget and Live Activities' processes respect.
    @ObservationIgnored private let lock: any SharedLock
    /// Why the theme can't change now (a shower or laundry run going on); nil when it can.
    @ObservationIgnored private let themeLock: @MainActor () -> ThemeLock?

    init(preference: ThemePreference, lock: any SharedLock, themeLock: @escaping @MainActor () -> ThemeLock?) {
        self.preference = preference
        self.lock = lock
        self.themeLock = themeLock
        theme = preference.theme
    }

    /// Saves the choice where the widget and the Live Activities read it, and has the widget
    /// draw again. Nothing changes while a run locks the theme (`ThemeLock`, whoever asks; 主题
    /// greys its options out too), or when the shared lock can't be taken (the container locked
    /// before the first unlock): the option stays unselected.
    @MainActor func select(_ theme: AppTheme) {
        do {
            guard try preference.select(theme, current:self.theme, lock:themeLock(), under:lock) else { return }
        } catch { return }
        self.theme = theme
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// After 重置校日常 cleared the stored choice: back to what is stored (暖橙).
    @MainActor func reload() {
        let stored = preference.theme
        if stored != theme { theme = stored }
    }
}
