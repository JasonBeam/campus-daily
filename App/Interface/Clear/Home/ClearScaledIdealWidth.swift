import SwiftUI

/// Reports its content's ideal width times `scale`, so a one-line text that may shrink to that
/// scale (`minimumScaleFactor`) counts as fitting in `ViewThatFits` when its shrunk line does.
/// Placed, the content gets the width offered as usual.
struct ClearScaledIdealWidth: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        guard proposal.width == nil else { return content.sizeThatFits(proposal) }
        let ideal = content.sizeThatFits(proposal)
        return CGSize(width:(ideal.width * scale).rounded(.up), height:ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at:bounds.origin, proposal:ProposedViewSize(bounds.size))
    }
}
