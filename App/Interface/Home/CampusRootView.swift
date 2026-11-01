import SwiftUI

/// Single-screen root (no tab bar); settings is a sheet from the home gear.
struct CampusRootView: View {
    var body: some View {
        HomeView().tint(Theme.accentText)
            // All UI copy is Simplified Chinese: pin the CJK font cascade to PingFang SC so the
            // system language can't pick another Han font (it made some strings render lighter).
            .typesettingLanguage(Theme.typesetting)
    }
}
