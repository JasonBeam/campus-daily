import SwiftUI

/// A problem's words in 清爽: in `notice` while they fit on one line (a short error), in the
/// secondary label colour once they run longer, so a paragraph doesn't read as one long alarm.
/// The mark beside them (a dot, an icon) keeps `notice` either way.
struct ClearNoticeText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        ViewThatFits(in:.horizontal) {
            Text(text).lineLimit(1).foregroundStyle(Theme.notice)
            Text(text).foregroundStyle(Color(uiColor:.secondaryLabel)).fixedSize(horizontal:false, vertical:true)
        }
    }
}
