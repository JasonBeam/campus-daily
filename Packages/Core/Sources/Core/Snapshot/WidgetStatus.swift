import Foundation

/// Which of the four widget states the stored data is in. Decided here from what
/// is stored (the shared snapshot and the saved account), never by the view.
public enum WidgetFreshness: String, Sendable, Equatable, CaseIterable {
    /// Numbers in ink, 「10:32 更新」.
    case fresh
    /// No saved password, and the card session could not be renewed or the last good update is
    /// over two hours old; or the saved password is held off after a login with no answer:
    /// numbers kept, time in ink3, 「打开 App 更新」.
    case stale
    /// A password is saved but the one automatic login with it failed: 「登录过期了」.
    case expired
    /// Nobody signed in: 「登录后显示余额和电量」.
    case never

    /// A tap opens the login step (expired, never) instead of the home screen.
    public var opensLogin: Bool { self == .expired || self == .never }
}

/// Where a tap on the widget goes.
public enum WidgetTap: String, Sendable, Equatable, CaseIterable {
    /// The home screen.
    case home
    /// The login step (expired, never signed in).
    case login
    /// Settings › 学校账号, which explains the paused automatic login.
    case account

    public var url: URL {
        switch self {
        case .home: return URL(string: "campusdaily://home")!
        case .login: return URL(string: "campusdaily://login")!
        case .account: return URL(string: "campusdaily://settings/account")!
        }
    }
}

public enum WidgetStatus {
    /// Without a saved password, numbers older than this are stale.
    public static let staleAfter: TimeInterval = 2 * 3600
    /// The widget skips its own read when the snapshot was checked this recently (by the app or
    /// by an earlier widget read): the numbers are as new as a read would make them.
    public static let minimumRefreshInterval: TimeInterval = 10 * 60

    /// The last successful update: the newer of the two tiles' `fetchedAt` (staleness).
    public static func lastUpdated(_ snapshot: HomeSnapshot) -> Date? {
        [snapshot.card.fetchedAt, snapshot.power.fetchedAt].compactMap { $0 }.max()
    }

    /// The time the 「… 更新」 footer shows: the oldest of the tiles that show a number, so a card
    /// balance read just now doesn't pass off a meter reading from days ago as new. Without any
    /// number, the newest update.
    public static func shownUpdated(_ snapshot: HomeSnapshot) -> Date? {
        let shown = [snapshot.card.value == nil ? nil : snapshot.card.fetchedAt,
                     snapshot.power.value == nil ? nil : snapshot.power.fetchedAt].compactMap { $0 }
        return shown.min() ?? lastUpdated(snapshot)
    }

    /// A password is saved (paused or not: either way the user chose automatic sign-in).
    public static func hasSavedPassword(_ account: SchoolAccount?) -> Bool {
        !(account?.password ?? "").isEmpty
    }

    /// - never: no snapshot, or the empty one a sign-out leaves.
    /// - expired: a saved password and the snapshot says the login is dead (the refresh ladder
    ///   ends with the saved password, so it was tried and refused or paused).
    /// - stale: the login is dead while a saved password is held off after a login that got no
    ///   answer (it resumes by itself, nothing is wrong with the password); or no saved password,
    ///   and the login is dead, nothing was ever read, or the last good update is more than
    ///   `staleAfter` before `now` (exactly `staleAfter` is still fresh).
    /// - fresh: otherwise.
    public static func freshness(snapshot: HomeSnapshot?, account: SchoolAccount?, now: Date) -> WidgetFreshness {
        guard let snapshot, snapshot != .empty else { return .never }
        if hasSavedPassword(account) {
            guard snapshot.needsLogin else { return .fresh }
            return account?.autoLogin(at: now) == .pausedNoAnswer ? .stale : .expired
        }
        if snapshot.needsLogin { return .stale }
        guard let last = lastUpdated(snapshot) else { return .stale }
        return now.timeIntervalSince(last) > staleAfter ? .stale : .fresh
    }

    /// Expired and never open the login step. Stale because a saved password is held off after
    /// a login with no answer opens Settings › 学校账号, where the hold is explained (logging in
    /// again would not help). Everything else opens the home screen.
    public static func tap(snapshot: HomeSnapshot?, account: SchoolAccount?, now: Date) -> WidgetTap {
        let state = freshness(snapshot: snapshot, account: account, now: now)
        if state.opensLogin { return .login }
        if state == .stale, account?.autoLogin(at: now) == .pausedNoAnswer { return .account }
        return .home
    }

    /// When a fresh state turns stale with time alone (for a second timeline entry), or nil
    /// when time alone never changes it.
    public static func staleAt(snapshot: HomeSnapshot?, account: SchoolAccount?, now: Date) -> Date? {
        guard freshness(snapshot: snapshot, account: account, now: now) == .fresh, !hasSavedPassword(account),
              let snapshot, let last = lastUpdated(snapshot) else { return nil }
        return last.addingTimeInterval(staleAfter + 1)
    }

    /// Whether the widget runs a school read before drawing: not when nobody is signed in, and
    /// not when the snapshot was checked less than `minimumRefreshInterval` ago.
    public static func shouldRefresh(snapshot: HomeSnapshot?, now: Date) -> Bool {
        guard let snapshot, snapshot != .empty else { return false }
        guard let checked = snapshot.checkedAt else { return true }
        let age = now.timeIntervalSince(checked)
        // A check stamped in the future (the clock moved back) counts as old.
        return age < 0 || age >= minimumRefreshInterval
    }
}
