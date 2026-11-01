import Foundation

/// When the automatic meter lookup (`SchoolSession.matchElectricity`) starts, and what it left on
/// screen. It starts at launch, after every sign-in (form or web page, any screen) and on
/// 「再找一次电表」, only signed in with no meter bound; never by itself in the foreground or
/// after a refresh. A sign-in while one runs is looked for once it ends (it may have brought
/// another dorm). A same-name list or a stopped level stays while a lookup runs again; its
/// answer replaces them. Pure; the app keeps one.
public struct MeterLookupGate: Sendable, Equatable {
    public enum Trigger: Sendable, Equatable, CaseIterable {
        /// The app's cold launch.
        case launch
        /// A sign-in of any kind.
        case signedIn
        /// 「再找一次电表」.
        case manual
    }

    public private(set) var running = false
    /// Same-name rooms to choose from (`.chooseAmong`).
    public private(set) var choices: [MeterCandidate] = []
    /// The person stamp of the lookup that offered `choices` (a pick after a switch is refused).
    public private(set) var choicesStamp: Int?
    /// Where the walk stopped (`.stopped`): the meter page opens there.
    public private(set) var stop: MeterWalkStop?
    /// The person stamp of the lookup that stopped (a pick of its candidates after a switch is refused).
    public private(set) var stopStamp: Int?
    /// Several apartments (or campuses) to tell apart, one not read (`.unfinished`): the meter
    /// page shows no list, only the message and 「再找一次电表」.
    public private(set) var unfinished: MeterWalkStop?
    private var signedInMeanwhile = false

    public init() {}

    /// Whether the lookup starts now.
    public mutating func start(_ trigger: Trigger, signedIn: Bool, meterBound: Bool) -> Bool {
        if running {
            if trigger == .signedIn { signedInMeanwhile = true }
            return false
        }
        guard signedIn, !meterBound else { return false }
        running = true
        return true
    }

    /// The lookup answered for the person still signed in: the answer replaces what was shown.
    /// `meterBound` = a meter is bound now (read again as the answer lands).
    @discardableResult
    public mutating func answered(_ found: ElectricityResolution, stamp: Int, meterBound: Bool = false) -> Bool {
        running = false
        clear()
        // A meter picked by hand meanwhile wins: the late list or stop is not shown.
        guard !meterBound else { return false }
        switch found {
        case .chooseAmong(let list): choices = list; choicesStamp = stamp
        case .stopped(let at): stop = at; stopStamp = stamp
        case .unfinished(let at): unfinished = at
        case .matched, .alreadyBound, .noAddress: break
        }
        return true
    }

    /// Where the meter page opens: the stopped level, unless a meter is bound by now.
    public func pageStop(meterBound: Bool) -> MeterWalkStop? {
        guard !meterBound, let stop, !stop.options.isEmpty else { return nil }
        return stop
    }

    /// The lookup ended. After `answered`, or alone when it failed or was dropped for another
    /// person (what was shown stays). True once when a sign-in came meanwhile: look again.
    public mutating func ended() -> Bool {
        running = false
        defer { signedInMeanwhile = false }
        return signedInMeanwhile
    }

    /// A sign-in, a sign-out or a meter chosen: nothing of the last lookup is shown. A lookup
    /// still running goes on (it checks the person itself).
    public mutating func clear() {
        choices = []; choicesStamp = nil; stop = nil; stopStamp = nil; unfinished = nil
    }
}
