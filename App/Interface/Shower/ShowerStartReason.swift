import SwiftUI
import Core

/// Why 开始洗澡 is greyed out, in the line under the button (both themes, `ShowerStartBlock`):
/// an `info.circle` and the reason in the footnote's secondary colour (an explanation, not an
/// error), up to 3 lines (5 at accessibility sizes), then its links 4 pt under it, side by
/// side while they fit.
struct ShowerStartReason<Links: View>: View {
    let text: String
    @ViewBuilder let links: Links
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment:.leading, spacing:4) {
            Label { Text(text) } icon: { Image(systemName:"info.circle").accessibilityHidden(true) }
                .font(.footnote).foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? 5 : 3)
                .fixedSize(horizontal:false, vertical:true)
                .accessibilityIdentifier("showerStartReason")
            // Two links side by side while they fit.
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.top, spacing:24) { links }
                VStack(alignment:.leading, spacing:0) { links }
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }
}

/// A reason's link: drawn as 「看校园卡记录 ›」 (accent 15 pt and a chevron), its text at the top
/// of a frame at least 44 pt tall. 清爽 takes its tint.
struct ShowerStartReasonLinkLabel: View {
    let text: String
    var clear = false

    static func style(clear: Bool) -> AccentChevronLabel.Style {
        clear ? AccentChevronLabel.Style(size:15, relativeTo:.subheadline, color:NativeTheme.tint) : ShowerCardRecordsLink.style
    }

    var body: some View {
        AccentChevronLabel(text:text, style:Self.style(clear:clear))
            .frame(minHeight:44, alignment:.top)
            .contentShape(Rectangle())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isButton)
    }
}

/// The start button while greyed out for the app still loading (`ShowerStartBlock.launching`):
/// the spinner of 正在处理…, without words, once `spinnerDelay` has gone by.
struct ShowerLaunchSpinner: ViewModifier {
    let launching: Bool
    @Binding var shown: Bool

    func body(content: Content) -> some View {
        content.task(id:launching) {
            guard launching else { shown = false; return }
            try? await Task.sleep(for:ShowerStartBlock.spinnerDelay)
            if !Task.isCancelled { shown = true }
        }
    }
}
