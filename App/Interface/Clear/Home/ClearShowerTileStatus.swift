import SwiftUI
import Core

/// The 热水 tile's status word: 可连接, 处理中, 已授权, 待核对 or 待配置.
struct ClearShowerTileStatus: View {
    let status: ShowerTileStatus

    var body: some View {
        ClearTileStatusLine(forms:status.forms.map { Text($0) })
            .foregroundStyle(Theme.ink2)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(status.spoken)
    }
}
