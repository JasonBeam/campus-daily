import SwiftUI

/// The modifiers SwiftUI hands to UIKit (a control's tint, a list row's or a sheet's background)
/// pass a `Color` through as it is but draw a custom `ShapeStyle` another way. Given a token, these
/// resolve it with the theme in the environment first, so they get the same `Color` they did
/// before the tokens were shape styles. (A toolbar item's label takes `color(_:)` itself: a
/// modifier around it changes how the bar draws its glass.)
extension View {
    func tint(_ token: ThemeColor) -> some View {
        modifier(ResolvedThemeColor(token:token, target:.tint))
    }

    func listRowBackground(_ token: ThemeColor?) -> some View {
        modifier(ResolvedThemeColor(token:token, target:.listRowBackground))
    }

    func presentationBackground(_ token: ThemeColor) -> some View {
        modifier(ResolvedThemeColor(token:token, target:.presentationBackground))
    }
}

private struct ResolvedThemeColor: ViewModifier {
    enum Target { case tint, listRowBackground, presentationBackground }

    @Environment(\.appTheme) private var theme
    let token: ThemeColor?
    let target: Target

    @ViewBuilder func body(content: Content) -> some View {
        let color: Color? = token?.color(theme)
        switch target {
        case .tint: content.tint(color)
        case .listRowBackground: content.listRowBackground(color)
        case .presentationBackground: content.presentationBackground(color ?? .clear)
        }
    }
}
