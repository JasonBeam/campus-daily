import SwiftUI

/// Under the last settings group: 「校日常 · 非学校官方应用」.
struct SettingsFooter: View {
    var body: some View {
        Text("校日常 · 非学校官方应用")
            .scaledFont(12, relativeTo:.caption).multilineTextAlignment(.center).foregroundStyle(Theme.ink2)
            .frame(maxWidth:.infinity).padding(.top,10)
    }
}
