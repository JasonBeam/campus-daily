import Foundation

/// Why a start or an end did not go through, in words the system shows (Siri, Shortcuts, the
/// Live Activity).
public struct ShowerActionFailure: Error, LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }

    public static let platformMissingText = "这个版本没带热水配置，热水暂时用不了。"

    /// The engine refused before anything happened.
    public init(_ error: ShowerEngineError) {
        switch error {
        case .busy: message = "正在和水控通信，稍等一下。"
        case .blocked: message = ShowerAuthorText.keptStatus
        case .notAllowed: message = "现在没有可以结束的洗澡。"
        case .wrongBinding: message = "这次洗澡用的不是你现在选的水控，打开校日常看看。"
        case .storage: message = "这台手机的钥匙串暂时写不进去，重启 App 后再试。"
        case .unreadableRecord: message = "读不到上次的热水记录，打开校日常看看。"
        case .platformMissing: message = Self.platformMissingText
        }
    }

    /// A start turned down while `failure` waits for its check. An authorize the platform
    /// answered unclearly settled nothing, so it isn't called a settlement.
    public static func blockedText(_ failure: ShowerFailure?) -> String {
        if failure?.reason.isUnclearAuthorize == true {
            return ShowerAuthorizeUnclearText.spoken(platformMessage: failure?.platformMessage)
        }
        return ShowerActionFailure(.blocked).message
    }

    /// What a start or an end that threw `error` says. `failure`: the record's failure at that
    /// moment, so a start the engine itself turned down says what waits (`blockedText`).
    /// `other`: the words for an error that is none of the shower's own.
    public static func thrown(_ error: Error, failure: ShowerFailure?, other: (Error) -> String) -> ShowerActionFailure {
        if let e = error as? ShowerActionFailure { return e }
        if let e = error as? ShowerEngineError { return e == .blocked ? ShowerActionFailure(blockedText(failure)) : ShowerActionFailure(e) }
        if let e = error as? ShowerDeviceError { return ShowerActionFailure(e.userText) }
        return ShowerActionFailure(other(error))
    }
}

public extension ShowerDeviceError {
    /// What the user can do about it.
    var userText: String {
        switch self {
        case .bluetoothOff: return "蓝牙没开，打开后再试。"
        case .notFound: return "附近没找到水控，靠近一点再试。"
        case .ambiguous: return "附近有好几台同名水控，没认出你宿舍的那台。靠近一点再试。"
        case .timedOut: return "水控没回应，靠近一点再试。"
        case .disconnected, .interrupted: return "和水控的连接断了，再试一次。"
        case .malformedFrame: return "水控回的内容看不懂，再试一次。"
        case .busy: return "正在和水控通信，稍等一下。"
        }
    }
}
