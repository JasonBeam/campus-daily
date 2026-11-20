#if DEBUG
import SwiftUI
import Core

/// campusdaily://demo/widget-preview[/2|/3|/4|/<face>] — draws the 「校日常」 widget views in the app at home-screen
/// sizes (small 170×170, medium 364×170, corner 22, 16pt margins), because widgets can't be
/// captured from the simulator CLI. Same view code as the widget; follows the system appearance.
struct WidgetPreview: View {
    @Environment(\.appTheme) private var appTheme
    struct Page: Identifiable { let number: Int; var id: Int { number } }
    /// Page 1, 2 or 3, nil when the URL is not a widget preview.
    static func handle(_ url: URL) -> Page? {
        let parts = Array(url.pathComponents.dropFirst())
        guard url.scheme == "campusdaily", url.host == "demo", parts.first == "widget-preview" else { return nil }
        let number = parts.count > 1 ? Int(parts[1]) ?? faces.firstIndex(of:parts[1]).map { $0 + 5 } ?? 1 : 1
        return Page(number:(1...(4 + faces.count)).contains(number) ? number : 1)
    }
    /// One face per page, small and medium, as the 暖橙 widget mockup lays them out: pages 5….
    static let faces = ["normal", "low", "never", "loading", "stale", "expired"]
    var page = 1
    @Environment(\.colorScheme) private var scheme
    /// Today at `hour:minute`, or a little before now when that is still to come.
    private func today(_ hour: Int, _ minute: Int, else minutesAgo: Double) -> Date {
        let now = Date()
        let time = Calendar.current.date(bySettingHour:hour, minute:minute, second:0, of:now) ?? now
        return time < now ? time : now.addingTimeInterval(-minutesAgo * 60)
    }
    private var updated: Date { today(10, 32, else:5) }
    private var staleTime: Date { today(8, 10, else:150) }
    /// 22:10 yesterday / 22:10 two days ago, for the footers that must name the day.
    private func daysAgo(_ days: Int) -> Date {
        let day = Calendar.current.date(byAdding:.day, value:-days, to:Date()) ?? Date()
        return Calendar.current.date(bySettingHour:22, minute:10, second:0, of:day) ?? day
    }
    private func model(_ state: WidgetFreshness = .fresh, power: String = "42.6", card: String = "86.50", extras: Bool = false,
                       at time: Date? = nil) -> CampusWidgetModel {
        CampusWidgetModel(state:state, remainingKWh:Decimal(string:power), balance:Decimal(string:card),
                          dailyAverageKWh:extras ? Decimal(string:"5.1") : nil,
                          powerBalance:extras ? Decimal(string:"23.40") : nil, updated:time ?? (state == .stale ? staleTime : updated))
    }
    /// Signed in, nothing read yet.
    private var firstRead: CampusWidgetModel { CampusWidgetModel(state:.fresh) }
    var body: some View {
        VStack(spacing:8) {
            switch page {
            case 1:
                // The four states, small and medium.
                HStack(spacing:24) {
                    tile(model(extras:true), caption:"正常 · 有日均")
                    tile(model(.stale), caption:"没存密码 · 过期")
                }
                HStack(spacing:24) {
                    tile(model(.expired), caption:"登录过期了")
                    tile(.never, caption:"从没登录")
                }
                tile(model(extras:true), medium:true, caption:"中号 · 正常")
                tile(model(.stale, extras:true), medium:true, caption:"中号 · 没存密码 · 过期")
            case 2:
                tile(model(.expired, extras:true), medium:true, caption:"中号 · 登录过期了")
                tile(.never, medium:true, caption:"中号 · 从没登录")
                HStack(spacing:24) {
                    tile(model(power:"4.8"), caption:"电量低（只有电量变红）")
                    tile(model(.stale, power:"4.8", card:"12.30"), caption:"过期 · 都低")
                }
            case 4:
                // Readings not from today: the footer names the day.
                HStack(spacing:24) {
                    tile(model(.stale, at:daysAgo(1)), caption:"过期 · 昨天")
                    tile(model(.stale, at:daysAgo(2)), caption:"过期 · 更早")
                }
                tile(model(.stale, extras:true, at:daysAgo(1)), medium:true, caption:"中号 · 过期 · 昨天")
                tile(model(extras:true, at:daysAgo(2)), medium:true, caption:"中号 · 存了密码 · 更早")
            case 5...:
                face(Self.faces[page - 5])
            default:
                HStack(spacing:24) {
                    tile(firstRead, caption:"登录了 · 还没数据")
                    tile(model(.expired, power:"4.8", card:"12.30"), caption:"登录过期 · 电量低 · 只留校园卡")
                }
                tile(firstRead, medium:true, caption:"中号 · 登录了 · 还没数据")
                tile(model(), medium:true, caption:"中号 · 没有每天约用和电费余额")
            }
        }
        .padding(.top,64)
        .frame(maxWidth:.infinity, maxHeight:.infinity, alignment:.top)
        .background((scheme == .dark ? Color(red:0.13, green:0.16, blue:0.20) : Color(red:0.80, green:0.84, blue:0.88)).ignoresSafeArea())
    }
    /// The mockup's screens: normal, low, never, loading (the grey bars), stale (with the small
    /// expired face beside it) and expired.
    @ViewBuilder private func face(_ name: String) -> some View {
        switch name {
        case "low":
            let low = lowModel
            HStack(spacing:24) { tile(low, caption:"电快用完"); tile(model(), caption:"平常") }
            tile(low, medium:true, caption:"中号 · 电快用完")
        case "never":
            HStack(spacing:24) { tile(.never, caption:"没登录"); tile(firstRead, caption:"登录了 · 还没数据") }
            tile(.never, medium:true, caption:"中号 · 没登录")
        case "loading":
            HStack(spacing:24) { tile(.placeholderFace, caption:"读取中"); tile(model(), caption:"平常") }
            tile(.placeholderFace, medium:true, caption:"中号 · 读取中")
        case "stale":
            HStack(spacing:24) {
                tile(model(.stale, at:daysAgo(1)), caption:"旧数")
                tile(model(.expired), caption:"登录过期")
            }
            tile(model(.stale, extras:true, at:daysAgo(1)), medium:true, caption:"中号 · 旧数")
        case "expired":
            HStack(spacing:24) { tile(model(.expired), caption:"登录过期"); tile(model(.expired, power:"4.8"), caption:"登录过期 · 电量低") }
            tile(model(.expired, extras:true), medium:true, caption:"中号 · 登录过期")
        default:
            HStack(spacing:24) { tile(model(), caption:"平常"); tile(model(power:"182.5"), caption:"电量满格") }
            tile(model(extras:true, at:today(22, 10, else:5)), medium:true, caption:"中号 · 平常")
        }
    }
    /// 6.8 度 left, 电费余额 ¥3.40.
    private var lowModel: CampusWidgetModel {
        var low = model(power:"6.8", extras:true, at:today(22, 10, else:5))
        low.powerBalance = Decimal(string:"3.40")
        return low
    }
    private func tile(_ model: CampusWidgetModel, medium: Bool = false, caption: String) -> some View {
        VStack(spacing:4) {
            CampusWidgetFace(model:model, medium:medium, theme:appTheme)
                .redacted(reason:model.placeholder ? .placeholder : [])
                .padding(16)
                .frame(width:medium ? 364 : 170, height:170)
                .background(ClearScriptsFace.draws(model, medium:medium, theme:appTheme) ? ClearScriptsFace.paper
                                : CampusWidgetPalette.of(appTheme).group, in:RoundedRectangle(cornerRadius:22, style:.continuous))
            Text(caption).font(.system(size:11, weight:.medium))
                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.6))
        }
    }
}
#endif
