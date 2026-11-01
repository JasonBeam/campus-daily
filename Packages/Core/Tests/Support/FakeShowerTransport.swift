import Foundation
import Core

/// Scripted BLE transport. Replies are consumed in order per `exchange`; a reply can be a
/// frame, a device error, or a hang (until cancelled). Records connects and writes.
public final class FakeShowerTransport: ShowerTransport, @unchecked Sendable {
    // @unchecked: state guarded by `lock`.
    public enum Reply: Sendable {
        case frame(Data)
        case fail(ShowerDeviceError)
        /// Suspends until the calling task is cancelled.
        case hang
        /// The frame, once `gate` yields (or finishes).
        case after(AsyncStream<Void>, Data)
    }

    public struct Connect: Sendable, Equatable {
        public var required: String?
        public var preferred: String?
        public init(required: String?, preferred: String?) { self.required = required; self.preferred = preferred }
    }

    private let lock = NSLock()
    private var _replies: [Reply] = []
    private var _connectResults: [Result<String, ShowerDeviceError>] = []
    private var _writes: [Data] = []
    private var _connects: [Connect] = []
    private var _disconnects = 0
    /// Peripheral returned when no connect result is scripted.
    public var defaultPeripheral = "PERIPHERAL-A"
    /// Called before each exchange reply is returned (e.g. to cancel a task mid-flow).
    public var onExchange: (@Sendable (Data) -> Void)?

    public init() {}

    public func script(_ replies: Reply...) { lock.withLock { _replies += replies } }
    public func scriptConnect(_ results: Result<String, ShowerDeviceError>...) { lock.withLock { _connectResults += results } }

    public var writes: [Data] { lock.withLock { _writes } }
    public var connects: [Connect] { lock.withLock { _connects } }
    public var disconnects: Int { lock.withLock { _disconnects } }
    public var pendingReplies: Int { lock.withLock { _replies.count } }

    public func connect(bleName: String, machineID: String, required: String?, preferred: String?) async throws -> String {
        let result: Result<String, ShowerDeviceError> = lock.withLock {
            _connects.append(Connect(required: required, preferred: preferred))
            // Like the real transport: the required, else the preferred peripheral is the one reached.
            return _connectResults.isEmpty ? .success(required ?? preferred ?? defaultPeripheral) : _connectResults.removeFirst()
        }
        return try result.get()
    }

    public func exchange(_ command: Data) async throws -> Data {
        let reply: Reply = lock.withLock {
            _writes.append(command)
            return _replies.isEmpty ? .fail(.timedOut) : _replies.removeFirst()
        }
        onExchange?(command)
        switch reply {
        case .frame(let f): return f
        case .fail(let e): throw e
        case .hang:
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 5_000_000) }
            throw ShowerDeviceError.interrupted
        case .after(let gate, let f):
            for await _ in gate { break }
            return f
        }
    }

    public func disconnect() async { lock.withLock { _disconnects += 1 } }
}

/// Synthetic frames for a synthetic controller id.
public enum FakeFrames {
    public static func identity(_ machineHex: String, tail: UInt8 = 0) -> Data {
        Data([0x55]) + HexCoding.data(machineHex)! + Data((0..<15).map { UInt8($0) &+ tail })
    }
    public static let ack = Data([0xAA, 1, 2, 3, 4, 5, 6, 7, 8])
    public static let active = Data([0xA5])
}
