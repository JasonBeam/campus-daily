import Foundation

/// Where `DebugEvent`s go. The app runs on a `LaunchDebugLog` (`DebugLogLaunch`), which becomes
/// a `FileDebugLog` once StoreKit says the install is TestFlight and keeps nothing otherwise;
/// `NoDebugLog` everywhere else (the sample, the widget). Recording never throws and never waits on the caller's work.
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
    /// Returns once the log knows whether it keeps anything (`LaunchDebugLog`); at once otherwise.
    func waitUntilResolved() async
}

public extension DebugLogSink {
    func flush() {}
    func waitUntilResolved() async {}
}

/// Records nothing, creates nothing.
public struct NoDebugLog: DebugLogSink {
    public init() {}
    public var isEnabled: Bool { false }
    public func record(_ event: DebugEvent) {}
    public func lines() -> [String] { [] }
    public func clear() {}
}
