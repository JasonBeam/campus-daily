import SwiftUI
import Core

/// 「先看看示例」 while it is shut (`LiveShowerGate`), in both themes: the entry's title in
/// `Theme.disabledText` (at least 4.5:1 on the page), told apart from the open entry by its shape,
/// not its colour: no chevron, no press highlight, not a button. Under it, 2 pt down and centred
/// like the title (and like the open entry and the buttons above it), `SampleCopy.entryRefused`
/// in the footnote size and the same colour. VoiceOver: the title,
/// 「不可用」, then the line.
struct SampleEntryRefused<Title: View>: View {
    /// The open entry's height, so the login step doesn't move when the gate changes.
    var minHeight: CGFloat = 44
    /// The title, in the open entry's font.
    @ViewBuilder let title: (Text) -> Title

    var body: some View {
        VStack(alignment:.center, spacing:2) {
            title(Text(SampleCopy.entry))
            Text(SampleCopy.entryRefused).font(.footnote)
                .fixedSize(horizontal:false, vertical:true)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.disabledText)
        .frame(maxWidth:.infinity, minHeight:minHeight, alignment:.center)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(SampleCopy.entry)
        .accessibilityValue(SampleCopy.entryUnavailable)
        .accessibilityHint(SampleCopy.entryRefused)
        .accessibilityIdentifier("sampleEntryRefused")
    }
}
