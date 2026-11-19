import Foundation

/// 清爽's meter page, 绑定宿舍电表: the chosen levels (or the prompt) over one note, 「选择位置」
/// over every level's list, and 「重新选择位置」 at the bottom.
public enum ClearMeterPageText {
    public static let title = "绑定宿舍电表"
    /// The automatic lookup's section.
    public static let section = "宿舍电表"
    public static let saved = "电表已保存"
    public static let note = "电表与热水水控是独立绑定，核对寝室后再保存。"
    public static let searchPrompt = "搜索楼栋或寝室"
    public static let confirm = "确认是我的寝室并保存"
    public static let rechoose = "重新选择位置"
    public static let reading = "正在读取电表信息…"
    /// The automatic lookup running, and the way to run it again after it failed.
    public static let matching = "正在匹配电表，可以先保存热水宿舍"
    public static let retryMatch = "重试匹配电表"

    /// 「北校区 · 东苑公寓 · 3栋」, or the prompt before any level is chosen.
    public static func path(_ names: [String]) -> String {
        names.isEmpty ? "选择校区、楼栋和寝室" : names.joined(separator: " · ")
    }

    /// Over the list: 「选择位置」 while choosing a level, 「核对电表」 over the meters.
    public static func listHeader(meters: Bool) -> String { meters ? "核对电表" : "选择位置" }
}
