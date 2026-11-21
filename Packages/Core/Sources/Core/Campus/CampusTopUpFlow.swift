//
//  CampusTopUpFlow.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/05.
//

import Foundation

public enum CampusTopUpEvent: Sendable, Equatable {
    /// 「打开微信」.
    case weChatTapped
    /// What `UIApplication.open` answered for WeChat.
    case weChatOpened(Bool)
    /// The scene became active (true) or left it (inactive or background).
    case scene(active: Bool)
}

public enum CampusTopUpEffect: Sendable, Equatable {
    /// Put the text on the general pasteboard. Always comes before `open`.
    case copy(String)
    case open(URL)
    /// VoiceOver hears the failure line, once per failure.
    case announceFailure
    /// Read the balances again in the background, with nothing on screen.
    case refreshBalances
}

/// The 校园充值 page's own state.
public struct CampusTopUpFlow: Sendable, Equatable {
    /// The line under the button.
    public enum Line: Sendable, Equatable {
        case none
        /// The name was copied (kept for when the user comes back).
        case copied
        /// WeChat did not open; the name is still copied.
        case weChatFailed
    }

    public private(set) var line = Line.none
    /// 先看看示例: the button works the same (it touches no account); nothing is read from the
    /// school after coming back.
    public let sample: Bool
    /// The button was tapped and may have taken the user out of the app.
    private var awaitingReturn = false
    /// The app left the active state since that tap.
    private var left = false

    public init(sample: Bool = false) { self.sample = sample }

    public mutating func handle(_ event: CampusTopUpEvent) -> [CampusTopUpEffect] {
        switch event {
        case .weChatTapped:
            line = .copied; awaitingReturn = true
            // Copy first: WeChat takes the app out of the front.
            return [.copy(CampusTopUp.serviceName), .open(CampusTopUp.weChat)]
        case .weChatOpened(let opened):
            guard !opened else { return [] }
            // Nothing took the user away: coming back later is not from this tap.
            if !left { awaitingReturn = false }
            guard line != .weChatFailed else { return [] }
            line = .weChatFailed
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
