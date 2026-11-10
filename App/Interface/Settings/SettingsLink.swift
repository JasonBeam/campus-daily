/// A settings row that opens a page. Each theme's settings page turns it into its own link
/// (暖橙: a pushed view; 清爽: a `ClearRoute`).
enum SettingsLink: Hashable {
    /// 学校账号.
    case account
    /// 宿舍; also 热水 while there is no hot-water binding (it is made by choosing the dorm).
    case dorm
    /// 电表.
    case meter
    /// 热水, once bound.
    case hotWater
    /// 常用洗衣机.
    case washer
    /// 外观 › 主题.
    case theme
}
