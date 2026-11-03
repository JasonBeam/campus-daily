import Foundation

/// What 开始洗澡 / 结束并结算 came to, for the callers that speak instead of showing the page:
/// Siri, Shortcuts and the Live Activity button. A start the controller did not confirm is
/// not called confirmed, and anything that did not go through carries its real reason.
public enum ShowerActionOutcome: Sendable, Equatable {
    /// The controller confirmed the authorization.
    case started
    /// The authorization was written but the controller did not confirm it (`writePending`).
    case startUnconfirmed
    /// The end was closed and settled (the amount is on the record's receipt).
    case settled

    public static let startedText = "水控连上了，按出水键开水。"
    public static let startUnconfirmedText = "\(ShowerDisplay.writeUnconfirmedHint)。打开校日常能看到计时。"
    public static let endNotSentText = "这次没能结束，打开校日常再试一次。"

    /// `result`: the record after the engine's start or finish. `notice`: the text of its notice
    /// (a device error, a busy controller…), preferred to the record's own title.
    public static func after(start: Bool, _ result: ShowerState, notice: String?) -> Result<ShowerActionOutcome, ShowerActionFailure> {
        if result.phase == .failed {
            if result.failure?.reason == .deviceUnavailable, let device = result.failure?.deviceError {
                return .failure(ShowerActionFailure(device.userText))
            }
            if result.failure?.reason.isUnclearAuthorize == true {
                return .failure(ShowerActionFailure(ShowerAuthorizeUnclearText.spoken(platformMessage: result.failure?.platformMessage)))
            }
            if result.failure?.reason == .authorizeRefused {
                return .failure(ShowerActionFailure(ShowerAuthorizeRefusedText.spoken))
            }
            return .failure(ShowerActionFailure(ShowerDisplay.failureTitle(result.failure)))
        }
        if start {
            switch result.phase {
            case .running: return .success(.started)
            case .writePending: return .success(.startUnconfirmed)
            default: return .failure(ShowerActionFailure(notice ?? ShowerDisplay(result).title))
            }
        }
        if result.phase == .done { return .success(.settled) }
        return .failure(ShowerActionFailure(notice ?? endNotSentText))
    }
}
