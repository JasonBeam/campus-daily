import SwiftUI

/// Error lines under the page's content: the icon in `notice`, the words too while they are one
/// line (`ClearNoticeText`). Cached data stays visible above them.
struct ClearLaundryIssueLines: View {
    let lines: [String]

    var body: some View {
        ForEach(lines, id:\.self) { line in
            Label {
                ClearNoticeText(line).fixedSize(horizontal:false, vertical:true)
            } icon: {
                Image(systemName:"exclamationmark.circle")
            }
            .font(.footnote)
            .foregroundStyle(Theme.notice)
            .frame(maxWidth:.infinity, alignment:.leading)
        }
    }
}
