import Foundation
import Core

/// Keeps every event it is given (and how often it was cleared). Lines read `name fields`,
/// with each tag written as `kind:tag`.
public final class RecordingDebugLog: DebugLogSink, @unchecked Sendable {
    // @unchecked: state guarded by `lock`.
    private let lock = NSLock()
    private var _events: [DebugEvent] = []
    private var _clears = 0
    public init() {}
    public var isEnabled: Bool { true }
    public func record(_ event: DebugEvent) { lock.withLock { _events.append(event) } }
    public func lines() -> [String] {
        events.map { e in
            let f = e.fields { "\($0.kind.rawValue):tag" }
            return f.isEmpty ? e.name : "\(e.name) \(f)"
        }
    }
    public func clear() { lock.withLock { _events = []; _clears += 1 } }
    public var events: [DebugEvent] { lock.withLock { _events } }
    public var clears: Int { lock.withLock { _clears } }
}

public enum DebugLogTesting {
    /// A new empty folder under the temporary directory.
    public static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("debuglog-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The values (and their upper, lower and hex-pair-spaced forms) that turn up in `text`.
    public static func leaks(_ secrets: [String], in text: String) -> [String] {
        var found: [String] = []
        let haystack = text.lowercased()
        for s in secrets where !s.isEmpty {
            let forms = [s, s.uppercased(), s.lowercased()]
            if forms.contains(where: { text.contains($0) }) || haystack.contains(s.lowercased()) { found.append(s) }
        }
        return found
    }
}
