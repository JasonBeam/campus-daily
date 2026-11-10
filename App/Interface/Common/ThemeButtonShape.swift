import SwiftUI

/// The outline of primary and secondary buttons: a capsule in 暖橙, a 12 pt continuous rounded
/// rectangle in 清爽. Heights are the same in both.
struct ThemeButtonShape: Sendable {
    let rounded: Bool

    var shape: AnyShape {
        rounded ? AnyShape(RoundedRectangle(cornerRadius:12, style:.continuous)) : AnyShape(Capsule())
    }
}
