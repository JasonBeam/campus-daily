import Foundation

/// What the school sign-in sheet shows while its web view is hidden (pure; the sheet feeds it page
/// starts and automation probes). The page stays hidden until the school's sign-in form is on
/// screen, so the redirects before it never flash; after the user signs in it is hidden again and
/// one of three stage lines is shown, always moving forward.
public struct CampusLoginProgress: Equatable, Sendable {
    public enum Stage: Int, Comparable, Sendable, CaseIterable {
        case signingIn, readingCard, readingPower
        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }
    public enum Phase: Equatable, Sendable {
        /// Sheet just opened (or sent back to the sign-in host): hidden until the form shows.
        case opening
        /// The school's sign-in form (or its own verification step) is on screen.
        case form
        /// Signed in; the app is reading.
        case working(Stage)
    }

    public static let openingText = "正在打开学校登录…"
    public static let slowText = "学校网站有点慢，再等一会儿。"
    /// A stage running longer than this adds `slowText`.
    public static let slowAfter: TimeInterval = 8
    /// Never keep the page hidden longer than this while opening (no form found: show what's there).
    public static let revealAfter: TimeInterval = 15

    public static let signInHost = "cas.gdbtu.edu.cn"
    public static let workingHosts: Set<String> = ["portal.gdbtu.edu.cn", "ecykt.gdbtu.edu.cn"]

    public private(set) var phase: Phase = .opening
    /// When the current phase / stage started.
    public private(set) var since: Date

    public init(now: Date = Date()) { since = now }

    public static func text(_ stage: Stage) -> String {
        switch stage {
        case .signingIn: return "正在登录学校账号…"
        case .readingCard: return "正在读校园卡…"
        case .readingPower: return "正在读电量…"
        }
    }

    /// Automation stage names (Shared/CampusLoginAutomation.js) → shown stage.
    public static func stage(automation: String) -> Stage? {
        switch automation {
        case "portal-profile", "waiting-profile", "waiting-portal": return .signingIn
        case "opening-wallet", "waiting-wallet", "wallet-ready": return .readingCard
        default: return nil
        }
    }

    /// Web view hidden behind the spinner.
    public var concealed: Bool { phase != .form }

    /// Main line under the spinner (nil while the form is shown).
    public var text: String? {
        switch phase {
        case .opening: return Self.openingText
        case .form: return nil
        case .working(let stage): return Self.text(stage)
        }
    }

    /// Second line once the current step has taken longer than `slowAfter`.
    public func slowNote(now: Date) -> String? {
        concealed && now.timeIntervalSince(since) > Self.slowAfter ? Self.slowText : nil
    }

    // MARK: Events

    /// A main-frame navigation started on `host`.
    public mutating func pageStarted(host: String?, now: Date = Date()) {
        guard let host else { return }
        if Self.workingHosts.contains(host) { advance(to:.signingIn, now:now) }
        else if host == Self.signInHost, case .working = phase { set(.opening, now:now) }
    }

    /// One automation probe result. `formVisible`: the sign-in page reports its form (or the
    /// school's own verification step) on screen.
    public mutating func probed(automation: String, formVisible: Bool, now: Date = Date()) {
        if automation == "login" {
            if formVisible, phase == .opening { set(.form, now:now) }
            return
        }
        if let stage = Self.stage(automation:automation) { advance(to:stage, now:now) }
    }

    /// The sign-in was read; the app is now reading the meter.
    public mutating func delivered(now: Date = Date()) { advance(to:.readingPower, now:now) }

    /// Timer tick: an opening page that never showed a form is revealed anyway.
    public mutating func tick(now: Date = Date()) {
        if phase == .opening, now.timeIntervalSince(since) > Self.revealAfter { set(.form, now:now) }
    }

    /// The page failed to load: show it (and the error line) instead of a spinner.
    public mutating func failed(now: Date = Date()) {
        if phase == .opening { set(.form, now:now) }
    }

    private mutating func advance(to stage: Stage, now: Date) {
        if case .working(let current) = phase, current >= stage { return }
        set(.working(stage), now:now)
    }

    private mutating func set(_ next: Phase, now: Date) {
        guard next != phase else { return }
        phase = next; since = now
    }
}
