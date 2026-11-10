import Foundation

/// The app's look, chosen in Settings › 外观 › 主题. Each theme has its own pages (暖橙's feature
/// folders, 清爽's `Interface/Clear`); data, copy and behaviour come from the same models in both.
public enum AppTheme: String, Sendable, CaseIterable, Equatable {
    /// 暖橙: warm orange, big rounded numbers. The default.
    case warm
    /// 清爽: the system grouped look of the original app, one blue tint.
    case clear

    public static let standard: AppTheme = .warm

    /// The stored value read back: anything this build doesn't know is the default.
    public init(stored: String?) {
        self = stored.flatMap(AppTheme.init(rawValue:)) ?? .standard
    }

    public var name: String {
        switch self {
        case .warm: return "暖橙"
        case .clear: return "清爽"
        }
    }

    /// The line under the name on the 主题 page.
    public var summary: String {
        switch self {
        case .warm: return "暖色，数字大，一页看完。"
        case .clear: return "蓝白配色，像系统自带的 App。"
        }
    }

    /// 主题 page footer, also the second line while the options are greyed out.
    public static let footer = "两套的功能和数据一样，只是样子和页面排法不同。小组件、锁屏和灵动岛也会跟着换。"

    /// VoiceOver for the settings row: 「主题，暖橙」.
    public var settingsRowLabel: String { "主题，" + name }

    /// VoiceOver for a greyed-out option: 「清爽，暂时不能选」.
    public var unavailableLabel: String { name + "，暂时不能选" }
}
