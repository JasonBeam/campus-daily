import SwiftUI

/// Each theme has its own page tree: 暖橙's is one home screen (`HomeView`, settings a sheet from
/// its gear), 清爽's a tab bar (`ClearRootView`). A theme switch replaces the whole tree, so it
/// lands on home with any sheet or pushed page closed. The theme comes from the injected
/// `ThemeStore` and goes down to every page as `\.appTheme`, which the tokens resolve from.
struct CampusRootView: View {
    @Environment(ThemeStore.self) private var store

    var body: some View {
        Group {
            switch store.theme {
            case .warm: HomeView()
            case .clear: ClearRootView()
            }
        }
        .tint(Theme.accentText)
        .environment(\.appTheme, store.theme)
        // All UI copy is Simplified Chinese: pin the CJK font cascade to PingFang SC so the
        // system language can't pick another Han font (it made some strings render lighter).
        .typesettingLanguage(Theme.typesetting)
    }
}
