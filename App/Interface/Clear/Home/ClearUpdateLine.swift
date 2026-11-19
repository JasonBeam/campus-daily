import SwiftUI
import Core

/// The bottom line of 电量和校园卡: 「10:32 更新」, or a failed read in the notice colour; an
/// expired login is a button to sign in again. Hidden while refreshing (the room line has the
/// spinner) and signed out.
struct ClearUpdateLine: View {
    let line: HomeUpdateLine
    var now = Date()
    var signIn: () -> Void = {}

    /// Whether there is a line to draw (none signed out or while refreshing).
    static func shows(_ line: HomeUpdateLine) -> Bool { line != .hidden && line != .refreshing }

    var body: some View {
        if let text = line.text(now:now, calendar:.current) {
            switch line {
            case .hidden, .refreshing:
                EmptyView()
            case .updated:
                Text(text).font(.footnote).foregroundStyle(Theme.ink2)
            case .failed, .notSaving:
                problem(text)
            case .expired:
                Button(action:signIn) { problem(text).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("homeLoginExpired")
            }
        }
    }

    private func problem(_ text: String) -> some View {
        HStack(alignment:.firstTextBaseline, spacing:5) {
            Image(systemName:"exclamationmark.circle").accessibilityHidden(true)
            ClearNoticeText(text).fixedSize(horizontal:false, vertical:true)
        }
        .font(.footnote).foregroundStyle(Theme.notice)
        .accessibilityElement(children:.combine)
    }
}
