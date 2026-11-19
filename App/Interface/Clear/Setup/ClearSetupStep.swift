import SwiftUI

/// A step page of the first-run checklist: heading and body, the step's content, and its
/// buttons in the bottom inset (at accessibility sizes they scroll with the content instead of
/// covering half the screen). Pushed from the checklist; it goes back there when the step is done.
struct ClearSetupStep<Content: View, Buttons: View>: View {
    /// The checklist row's title, inline in the nav bar.
    let navTitle: String
    let heading: String
    var message: String?
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:24) {
                VStack(alignment:.leading, spacing:8) {
                    Text(heading).font(.title2.bold()).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal:false, vertical:true)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message).font(.subheadline).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal:false, vertical:true)
                    }
                }
                content
                if typeSize.isAccessibilitySize { buttonStack }
            }
            .padding(20)
            .frame(maxWidth:560, alignment:.leading)
            .frame(maxWidth:.infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg)
        .safeAreaInset(edge:.bottom, spacing:0) {
            if !typeSize.isAccessibilitySize {
                buttonStack
                    .padding(.horizontal,20).padding(.vertical,12)
                    .frame(maxWidth:600)
                    .frame(maxWidth:.infinity)
                    .background(Theme.bg)
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accentText)
    }

    private var buttonStack: some View {
        VStack(spacing:4) { buttons }
    }
}
