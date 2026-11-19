import Foundation

/// The status line of 清爽 home's 热水 tile: one short word for the state, and how the tile behaves.
public struct ShowerTileStatus: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case secondary, notice, accent }

    public var text: String
    public var tone: Tone
    /// Showering: a running mm:ss follows the text, counted from here.
    public var timerStart: Date?
    /// Shorter ways to say it, shortest last, for a tile too narrow for `text` on one line:
    /// 「11 分钟 · ¥1.32」 then 「¥1.32」; showering, "" (the timer alone). VoiceOver reads `text`.
    public var shorter: [String]
    /// Hot water can't be used here (not set up, not available): the tile is dimmed but still
    /// opens its page.
    public var dimmed = false
    /// Signed out: the tile opens the first-run checklist instead of the page.
    public var opensSetup = false
    /// What VoiceOver reads when it differs from `text` (「去洗澡，上一次洗好了」).
    public var spokenText: String?
    /// What VoiceOver reads.
    public var spoken: String { spokenText ?? text }

    public init(text: String, tone: Tone = .secondary, timerStart: Date? = nil, shorter: [String] = [], dimmed: Bool = false,
                opensSetup: Bool = false) {
        self.text = text; self.tone = tone; self.timerStart = timerStart; self.shorter = shorter; self.dimmed = dimmed
        self.opensSetup = opensSetup
    }

    /// `text`, then the shorter ways to say it.
    public var forms: [String] { [text] + shorter }

    /// The tile's second line: the dorm while signed in; signed out or with no dorm, no line
    /// (not a dorm left over from before the sign-out).
    public static func dormLine(_ dorm: String?, signedIn: Bool) -> String? {
        guard signedIn, let dorm, !dorm.isEmpty else { return nil }
        return dorm
    }

    /// One short word per state: 「可连接」, 「处理中」 while starting or settling, 「已授权」 while
    /// water runs, 「待核对」 for a problem or a shower that is over, 「待配置」 before hot water is
    /// set up. `lastMinutes`, `lastCost`: the last shower has its own card on home.
    public static func of(_ status: ShowerHomeStatus, signedIn: Bool, lastMinutes: Int?, lastCost: Decimal?,
                          issue: String?) -> ShowerTileStatus {
        if status.asksForSchoolSignIn(signedIn: signedIn) { return ShowerTileStatus(text: Words.setUp, opensSetup: true) }
        switch status {
        case .unconfigured: return ShowerTileStatus(text: Words.setUp)
        case .unavailable(let reason): return ShowerTileStatus(text: reason, dimmed: true)
        case .idle: return ShowerTileStatus(text: issue == nil ? Words.ready : Words.check)
        case .starting, .settling: return ShowerTileStatus(text: Words.busy)
        case .showering: return ShowerTileStatus(text: Words.authorized)
        // Over (stopped on the controller, or kept for the school): the tile opens the timer page.
        case .stopped: return ShowerTileStatus(text: Words.check)
        }
    }

    public enum Words {
        public static let ready = "可连接"
        public static let busy = "处理中"
        public static let authorized = "已授权"
        public static let check = "待核对"
        public static let setUp = "待配置"
    }
}
