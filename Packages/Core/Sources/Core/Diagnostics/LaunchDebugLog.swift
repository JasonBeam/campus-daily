import Foundation

/// Where the app was installed from, as StoreKit's app transaction says (`AppStore.Environment`).
public enum InstallEnvironment: Sendable, Equatable {
    /// TestFlight.
    case sandbox
    /// The App Store.
    case production
    /// StoreKit testing in Xcode.
    case xcode
    /// Anything StoreKit adds later.
    case other
}

/// Asks where the app was installed from. The app's is StoreKit's `AppTransaction.shared`;
/// tests give their own answer, error or silence.
public protocol InstallEnvironmentSource: Sendable {
    func environment() async throws -> InstallEnvironment
}

/// What the launch log does once it knows (`DebugLogLaunch.decision`).
public enum DebugLogDecision: Sendable, Equatable {
    /// Keep the log on disk and replay what was held.
    case testFlight
    /// Keep nothing and delete a log left by a TestFlight build.
    case appStore
    /// No answer (a timeout, an error, an Xcode run): keep nothing, delete nothing.
    case undetermined
}

public enum DebugLogLaunch {
    /// How long launch waits for StoreKit before giving up (`undetermined`).
    public static let timeout: TimeInterval = 5

    /// `sandbox` is TestFlight, `production` the App Store; anything else, an error or no answer
    /// within `timeout` is `undetermined`. Never waits past `timeout`, even if the source does.
    public static func decision(from source: any InstallEnvironmentSource, timeout: TimeInterval = DebugLogLaunch.timeout) async -> DebugLogDecision {
        let environment: InstallEnvironment? = await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let work = Task { once.resume(try? await source.environment()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                once.resume(nil)
                work.cancel()
            }
        }
        switch environment {
        case .sandbox: return .testFlight
        case .production: return .appStore
        case .xcode, .other, nil: return .undetermined
        }
    }

    /// The app's log: holds lines in memory while `source` is asked, then resolves.
    public static func start(applicationSupport: URL?, source: any InstallEnvironmentSource,
                             timeout: TimeInterval = DebugLogLaunch.timeout,
                             now: @escaping @Sendable () -> Date = Date.init) -> LaunchDebugLog {
        let log = LaunchDebugLog(applicationSupport: applicationSupport, now: now)
        Task.detached(priority: .utility) {
            log.resolve(await decision(from: source, timeout: timeout))
        }
        return log
    }

    private final class Once: @unchecked Sendable {
        // @unchecked: `continuation` is touched only under `lock`.
        private let lock = NSLock()
        private var continuation: CheckedContinuation<InstallEnvironment?, Never>?
        init(_ c: CheckedContinuation<InstallEnvironment?, Never>) { continuation = c }
        func resume(_ value: InstallEnvironment?) {
            let c: CheckedContinuation<InstallEnvironment?, Never>? = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            c?.resume(returning: value)
        }
    }
}

/// The log the app starts with. Until `resolve`, it holds at most `bufferLimit` lines in memory
/// (never on disk) and is off (`isEnabled` false: no export or clear row). On
/// `testFlight` it becomes a `FileDebugLog` (week-old lines dropped) and replays what it held,
/// each line with its own time; on `appStore` it drops them and deletes a log a TestFlight build
/// left; on `undetermined` it drops them and leaves the folder alone. Only the first answer counts.
public final class LaunchDebugLog: DebugLogSink, @unchecked Sendable {
    // @unchecked: the fields below `lock` are touched only under it.
    public static let bufferLimit = 200

    private let applicationSupport: URL?
    private let now: @Sendable () -> Date
    private let bufferLimit: Int
    private let lock = NSLock()
    private var held: [(DebugEvent, Date)] = []
    private var clearedWhileHeld = false
    private var file: FileDebugLog?
    private var _decision: DebugLogDecision?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(applicationSupport: URL?, now: @escaping @Sendable () -> Date = Date.init, bufferLimit: Int = LaunchDebugLog.bufferLimit) {
        self.applicationSupport = applicationSupport; self.now = now; self.bufferLimit = bufferLimit
    }

    /// nil until resolved.
    public var decision: DebugLogDecision? { lock.withLock { _decision } }

    public var isEnabled: Bool { lock.withLock { file != nil } }

    public func record(_ event: DebugEvent) {
        let at = now()
        let target: FileDebugLog? = lock.withLock {
            if _decision == nil {
                held.append((event, at))
                if held.count > bufferLimit { held.removeFirst(held.count - bufferLimit) }
            }
            return file
        }
        target?.record(event, at: at)
    }

    public func lines() -> [String] { current()?.lines() ?? [] }

    public func clear() {
        let target: FileDebugLog? = lock.withLock {
            if _decision == nil { held = []; clearedWhileHeld = true }
            return file
        }
        target?.clear()
    }

    public func flush() { current()?.flush() }

    public func waitUntilResolved() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let ready: Bool = lock.withLock {
                if _decision != nil { return true }
                waiters.append(c)
                return false
            }
            if ready { c.resume() }
        }
    }

    public func resolve(_ decision: DebugLogDecision) {
        // Under the lock throughout, so no line is recorded between the replay and the switch.
        let resumed: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard _decision == nil else { return [] }
            _decision = decision
            if let applicationSupport {
                let folder = FileDebugLog.directory(in: applicationSupport)
                switch decision {
                case .testFlight:
                    let log = FileDebugLog(directory: folder, now: now)
                    if clearedWhileHeld { log.clear() }
                    log.pruneExpired()
                    for (event, at) in held { log.record(event, at: at) }
                    file = log
                case .appStore:
                    if FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) }
                case .undetermined:
                    break
                }
            }
            held = []
            defer { waiters = [] }
            return waiters
        }
        resumed.forEach { $0.resume() }
    }

    private func current() -> FileDebugLog? { lock.withLock { file } }
}
