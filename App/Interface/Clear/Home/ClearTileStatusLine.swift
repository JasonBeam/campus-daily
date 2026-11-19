import SwiftUI

/// A tile's status on one line and never cut off: the first of `forms` (longest first) that fits
/// the tile's width; none fits, the shortest shrunk to 85%; not even that, the shortest over two
/// lines. The caller gives VoiceOver the whole sentence.
struct ClearTileStatusLine: View {
    let forms: [Text]

    var body: some View {
        let shortest = forms.last ?? Text("")
        ViewThatFits(in:.horizontal) {
            ForEach(forms.indices, id:\.self) { forms[$0].lineLimit(1) }
            ClearScaledIdealWidth(scale:0.85) { shortest.lineLimit(1).minimumScaleFactor(0.85) }
            shortest.fixedSize(horizontal:false, vertical:true)
        }
    }
}
