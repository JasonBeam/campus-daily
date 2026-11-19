import SwiftUI
import Core

/// 「用学校网页登录」: the school's web login as a small text link, the form's last row, in every
/// state (dimmed while logging in). Left-aligned, its own width, at least 44 pt tall.
struct SchoolWebLoginLink: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.isEnabled) private var enabled
    let action: () -> Void

    var body: some View {
        Button(action:action) {
            label
                .frame(minHeight:44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(SchoolLoginText.webLogin(appTheme))
        .accessibilityHint(SchoolLoginText.webLoginHint)
        .accessibilityIdentifier("webLogin")
    }

    @ViewBuilder private var label: some View {
        switch appTheme {
        case .warm:
            HStack(spacing:4) {
                Text(SchoolLoginText.webLogin(appTheme)).scaledFont(15, relativeTo:.subheadline).foregroundStyle(Theme.ink2)
                Image(systemName:"chevron.right").scaledFont(12, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.ink3)
            }
        case .clear:
            Text(SchoolLoginText.webLogin(appTheme)).font(.footnote).foregroundStyle(Theme.accentText)
        }
    }
}
