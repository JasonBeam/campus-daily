import SwiftUI
import UIKit
import Core

/// The explainer shown once before Bluetooth is first asked for (`ShowerStartIntent`): nothing
/// is created or asked until 好，开始; 等会儿 or swiping it down leaves everything as it was.
struct FirstCheckExplainer: View {
    let clear: Bool
    let confirm: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment:.leading, spacing:16) {
            Image(systemName:"checkmark.shield").font(.title).foregroundStyle(NativeTheme.tint).accessibilityHidden(true)
            Text(FirstCheckText.explainerTitle(clear:clear)).font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text(FirstCheckText.explainerBody(clear:clear)).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal:false, vertical:true)
            Spacer(minLength:8)
            Button(action:confirm) {
                Text(FirstCheckText.explainerConfirm(clear:clear)).frame(maxWidth:.infinity).frame(minHeight:50)
            }
            .buttonStyle(ShowerButtonStyle(primary:true, accent:NativeTheme.tint))
            .accessibilityIdentifier("firstCheckConfirm")
            Button(action:later) {
                Text(FirstCheckText.explainerLater(clear:clear)).frame(maxWidth:.infinity).frame(minHeight:44)
            }
            .accessibilityIdentifier("firstCheckLater")
        }
        .padding(24)
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.top)
        .background(NativeTheme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Opaque: the 热水洗澡 screen's button must not show through under 等会儿.
        .presentationBackground(NativeTheme.background)
    }
}

/// While a first check reads the number: under the button, what this step does (and doesn't).
struct FirstCheckCheckingLine: View {
    let clear: Bool
    var body: some View {
        Label { Text(FirstCheckText.checkingLine(clear:clear)) } icon: {
            ProgressView().controlSize(.mini).accessibilityHidden(true)
        }
        .font(.footnote).foregroundStyle(.secondary)
        .fixedSize(horizontal:false, vertical:true)
        .frame(maxWidth:.infinity, alignment:.leading)
        .accessibilityIdentifier("firstCheckChecking")
    }
}

/// Why the last first check came to nothing (nothing was authorized), in the notice colour,
/// with its one link (改宿舍 / 去设置) when it has one.
struct FirstCheckFailureLine: View {
    let failure: FirstCheckFailure
    let clear: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment:.leading, spacing:4) {
            Label { Text(failure.text(clear:clear)) } icon: {
                Image(systemName:"exclamationmark.circle").accessibilityHidden(true)
            }
            .font(.footnote).foregroundStyle(NativeTheme.notice)
            .lineLimit(typeSize.isAccessibilitySize ? 6 : 4)
            .fixedSize(horizontal:false, vertical:true)
            .accessibilityIdentifier("firstCheckFailure")
            if let link = failure.link {
                let title = FirstCheckFailure.linkTitle(link, clear:clear)
                switch link {
                case .dorm:
                    if clear {
                        NavigationLink(value:ClearRoute.dorm) { ShowerStartReasonLinkLabel(text:title, clear:true) }
                            .buttonStyle(RowPressStyle())
                    } else {
                        NavigationLink { CampusOnboardingView() } label: { ShowerStartReasonLinkLabel(text:title) }
                            .buttonStyle(RowPressStyle())
                    }
                case .settings:
                    if let url = URL(string:UIApplication.openSettingsURLString) {
                        Link(destination:url) { ShowerStartReasonLinkLabel(text:title, clear:clear) }
                    }
                }
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }
}

/// 「找到了，是你宿舍的水控。」 for a moment after the number matched.
struct FirstCheckPassedToast: View {
    let clear: Bool
    var body: some View {
        Label(FirstCheckText.passed(clear:clear), systemImage:"checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal,16).padding(.vertical,10)
            .foregroundStyle(Theme.ink)
            .background(NativeTheme.surface, in:Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color:.black.opacity(0.12), radius:12, y:4)
            .accessibilityIdentifier("firstCheckPassed")
    }
}

extension View {
    /// The explainer over this screen while the model's start waits for it.
    func firstCheckExplainer(_ shower: ShowerModel, clear: Bool) -> some View {
        modifier(FirstCheckExplainerSheet(shower:shower, clear:clear))
    }

    /// The short 「找到了」 over the top of this screen.
    func firstCheckPassedToast(_ shower: ShowerModel, clear: Bool) -> some View {
        overlay(alignment:.top) {
            if shower.checkToastShown {
                FirstCheckPassedToast(clear:clear).padding(.top,8).transition(.opacity)
                    .onAppear { UIAccessibility.post(notification:.announcement, argument:FirstCheckText.passed(clear:clear)) }
            }
        }
        .animation(.easeInOut(duration:0.2), value:shower.checkToastShown)
    }
}

private struct FirstCheckExplainerSheet: ViewModifier {
    @ObservedObject var shower: ShowerModel
    let clear: Bool

    func body(content: Content) -> some View {
        let id = shower.explainerIntent?.id
        content.sheet(isPresented:Binding(get:{ id != nil }, set:{ shown in
            if !shown, let id { shower.cancelExplainer(id) }
        })) {
            FirstCheckExplainer(clear:clear,
                                confirm:{ if let id { shower.confirmExplainer(id) } },
                                later:{ if let id { shower.cancelExplainer(id) } })
        }
    }
}
