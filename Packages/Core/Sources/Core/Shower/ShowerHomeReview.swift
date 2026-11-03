import Foundation

/// The home card of a record that waits for its check. An authorize the platform answered in a
/// way the app can't read, or with an authorization that can't be used, started no water and settled nothing, so it says the water didn't
/// start (with the platform's words when it gave any); every other record keeps the settlement
/// words.
public struct ShowerHomeReview: Equatable, Sendable {
    /// The button.
    public let button: String
    /// The accent line under it.
    public let caption: String

    public init(button: String, caption: String) {
        self.button = button; self.caption = caption
    }

    public static let settlement = ShowerHomeReview(button: "核对上次结算", caption: "上次洗澡不确定结算了没有")

    public init(_ failure: ShowerFailure?) {
        if let failure, failure.reason.isUnclearAuthorize {
            self.init(button: "去核对", caption: ShowerAuthorizeUnclearText.title(platformMessage: failure.platformMessage))
        } else {
            self = .settlement
        }
    }
}
