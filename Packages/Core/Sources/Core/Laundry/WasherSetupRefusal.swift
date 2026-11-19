import Foundation

/// Why choosing or saving a common washer did not go ahead, each with its own text.
public enum WasherSetupRefusal: Error, Equatable, Sendable {
    /// A laundry order is still open: machines don't change until it is checked.
    case orderOpen
    /// A machine read or an order step is running.
    case busy
    /// The machine is no longer in the saved list.
    case notSaved
    /// Nothing scanned to save.
    case nothingToSave
    /// Empty, over 40 characters, or with a line break or other control character.
    case badName

    public var message: String {
        switch self {
        case .orderOpen: return "先核对已有洗衣订单。"
        case .busy: return "正在处理上一步，稍等一下。"
        case .notSaved: return "这台机器不在常用列表里了，再扫一次机身二维码。"
        case .nothingToSave: return "先扫一次机身二维码。"
        case .badName: return "机器名称最多 40 个字。"
        }
    }

    /// The refusal for changing machines now, or nil when it may go ahead. An open order wins:
    /// waiting does not help there.
    public static func check(orderOpen: Bool, busy: Bool) -> WasherSetupRefusal? {
        if orderOpen { return .orderOpen }
        return busy ? .busy : nil
    }

    /// The name to save (trimmed), or `.badName`.
    public static func machineName(_ name: String) -> Result<String, WasherSetupRefusal> {
        let alias = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty, alias.count <= 40, alias.rangeOfCharacter(from: .controlCharacters) == nil else {
            return .failure(.badName)
        }
        return .success(alias)
    }
}
