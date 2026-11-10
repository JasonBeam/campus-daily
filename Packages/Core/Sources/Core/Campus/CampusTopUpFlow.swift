import Foundation

public enum CampusTopUpEvent: Sendable, Equatable {
    case weChatTapped
    case webTapped
    /// What `UIApplication.open` answered for WeChat.
    case weChatOpened(Bool)
    /// The scene became active (true) or left it (inactive or background).
    case scene(active: Bool)
}

public enum CampusTopUpEffect: Sendable, Equatable {
    case open(URL)
    /// VoiceOver hears the failure line, once per failure.
    case announceFailure
    /// Read the balances again in the background, with nothing on screen.
    case refreshBalances
}

/// The 校园充值 page's own state.
public struct CampusTopUpFlow: Sendable, Equatable {
    /// WeChat did not open: the footnote turns into the failure line.
    public private(set) var weChatFailed = false
    /// 先看看示例: nothing is read from the school.
    public let sample: Bool
    /// A button was tapped and may have taken the user out of the app.
    private var awaitingReturn = false
    /// The app left the active state since that tap.
    private var left = false

    public init(sample: Bool = false) { self.sample = sample }

    public mutating func handle(_ event: CampusTopUpEvent) -> [CampusTopUpEffect] {
        switch event {
        case .weChatTapped:
            weChatFailed = false; awaitingReturn = true
            return [.open(CampusTopUp.weChat)]
        case .webTapped:
            weChatFailed = false; awaitingReturn = true
            return [.open(CampusTopUp.web)]
        case .weChatOpened(let opened):
            guard !opened else { return [] }
            // Nothing took the user away: coming back later is not from this tap.
            if !left { awaitingReturn = false }
            guard !weChatFailed else { return [] }
            weChatFailed = true
            return [.announceFailure]
        case .scene(active: false):
            if awaitingReturn { left = true }
            return []
        case .scene(active: true):
            guard awaitingReturn, left else { return [] }
            awaitingReturn = false; left = false
            return sample ? [] : [.refreshBalances]
        }
    }
}
