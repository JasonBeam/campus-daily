import SwiftUI
import UIKit
import Core

/// 「去学校官网处理」: the school's login page in Safari (outside the app), where a captcha, an
/// extra check or a password change is done. Back in the app the password login is tried again.
struct SchoolSiteButton: View {
    @Environment(\.appTheme) private var appTheme

    /// The school's own CAS login page.
    static var url: URL { SchoolEndpoints.casLoginURL }

    var body: some View {
        switch appTheme {
        case .warm:
            Button(action:open) {
                HStack(spacing:6) {
                    Image(systemName:"arrow.up.right").font(.system(size:13, weight:.semibold))
                    Text(SchoolLoginText.schoolSite(appTheme))
                }
                .scaledFont(15, .medium).foregroundStyle(Theme.ink)
                .padding(.horizontal,16)
                .frame(minHeight:44)
                .background(Theme.fill, in:appTheme.buttonShape.shape)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityIdentifier("schoolSite")
        case .clear:
            Button(action:open) {
                Label(SchoolLoginText.schoolSite(appTheme), systemImage:"arrow.up.right")
            }
            .buttonStyle(.bordered).controlSize(.regular)
            .tint(Theme.accentText)
            .accessibilityIdentifier("schoolSite")
        }
    }

    private func open() {
        UIApplication.shared.open(Self.url)
    }
}
