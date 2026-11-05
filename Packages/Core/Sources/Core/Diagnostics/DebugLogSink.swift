import Foundation

/// Where `DebugEvent`s go. The app picks one at launch (`DebugLogLaunch`): `FileDebugLog` in a
/// TestFlight install, `NoDebugLog` everywhere else (the App Store, Xcode installs, the sample,
/// the widget). Recording never throws and never waits on the caller's work.
public protocol DebugLogSink: Sendable {
    /// False: nothing is kept (and the feedback form offers nothing to attach).
    var isEnabled: Bool { get }
    func record(_ event: DebugEvent)
    /// The kept lines, oldest first, as they would be sent (`MM-dd HH:mm:ss name fields`).
    func lines() -> [String]
    /// Empties the log and drops its salt (sign-outs, 清空调试记录); the next line starts a new one.
    func clear()
    /// Returns once every line recorded before it is on disk (the feedback send, its preview, tests).
    func flush()
}

public extension DebugLogSink {
    func flush() {}
}

/// Records nothing, creates nothing.
public struct NoDebugLog: DebugLogSink {
    public init() {}
    public var isEnabled: Bool { false }
    public func record(_ event: DebugEvent) {}
    public func lines() -> [String] { [] }
    public func clear() {}
}
