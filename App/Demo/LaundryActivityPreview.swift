#if DEBUG
import SwiftUI
import Core

/// campusdaily://demo/laundry-activity/preview[-done] — draws the Live Activity views in the app,
/// because the simulator can't host Live Activities (ActivityKit fails to connect). Same view code
/// as the widget; the island shapes and lock-screen backdrop are approximations.
struct LaundryActivityPreview: View {
    enum Kind: String, Identifiable { case running = "preview", done = "preview-done"; var id: String { rawValue } }
    static func handle(_ url: URL) -> Kind? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "laundry-activity", parts.count > 1 else { return nil }
        return Kind(rawValue:parts[1])
    }
    let kind: Kind
    private let attributes = LaundryActivityAttributes(orderId:"demo", machine:"3 号机", program:"标准洗")
    private var state: LaundryActivityAttributes.ContentState {
        let end = Date().addingTimeInterval(18 * 60)
        return .init(phase:kind == .done ? .done : .running, startedAt:end.addingTimeInterval(-45 * 60),
                     endsAt:end)
    }
    var body: some View {
        VStack(spacing:14) {
            // Compact island
            HStack {
                Image(systemName:LaundryActivityStyle.glyph).foregroundStyle(LaundryActivityStyle.accent)
                Spacer()
                LaundryIslandCompactTrailing(state:state)
            }
            .padding(.horizontal,16).frame(width:250, height:37).background(.black, in:Capsule())
            caption("灵动岛收起")
            // Expanded island
            VStack(spacing:6) {
                HStack { LaundryIslandLeading(attributes:attributes, state:state); Spacer(); LaundryIslandTrailing(attributes:attributes, state:state) }
                LaundryIslandBottom(state:state)
            }
            .padding(.horizontal,20).padding(.vertical,16)
            .background(.black, in:RoundedRectangle(cornerRadius:44, style:.continuous))
            .padding(.horizontal,8)
            caption("灵动岛展开")
            // Lock screen
            LaundryActivityLockView(attributes:attributes, state:state)
                .background(LaundryActivityStyle.background, in:RoundedRectangle(cornerRadius:24, style:.continuous))
                .padding(.horizontal,10)
            caption("锁屏")
            Spacer()
        }
        .padding(.top,70)
        .frame(maxWidth:.infinity, maxHeight:.infinity)
        .background(Color(red:0.68, green:0.75, blue:0.80).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size:12)).foregroundStyle(.white.opacity(0.8))
    }
}
#endif
