import Foundation

/// The hot-water controller's BLE protocol (ported as-is from the existing iOS/Android code;
/// the byte format must not change).
///
/// - GATT: service `FFE0`, notify `FFE1`, write `FFE2` (write with response).
/// - Probe: write `AA`. Reply is either the 20-byte identity frame `55 <machineId:4> <15 bytes>`
///   (controller idle) or the single byte `A5` (controller in use).
/// - Authorization: write the 15-byte `systemData` from the authorize reply; the controller
///   acks with a 9-byte frame starting `AA`.
/// - Close: write `AC <authorizationId XOR 55>` (5 bytes); the controller answers with a
///   20-byte `55` consumption frame carrying its identity, which is what gets settled.
public enum ShowerFrames {
    public static let serviceUUID = "FFE0"
    public static let notifyUUID = "FFE1"
    public static let writeUUID = "FFE2"

    public static let probeCommand = Data([0xAA])
    public static let activeReply = Data([0xA5])

    public static let identityFrameLength = 20
    public static let ackLength = 9
    public static let authorizationLength = 15
    public static let closeCommandLength = 5

    /// Machine id (upper hex) of a 20-byte `55` frame, else nil.
    public static func identity(_ frame: Data) -> String? {
        guard frame.count == identityFrameLength, frame.first == 0x55 else { return nil }
        return HexCoding.upper(Data(frame.dropFirst().prefix(4)))
    }

    /// The authorization write was acknowledged (9 bytes, first `AA`).
    public static func isAck(_ frame: Data) -> Bool { frame.count == ackLength && frame.first == 0xAA }

    public static func isActive(_ frame: Data) -> Bool { frame == activeReply }

    /// `AC` + each byte of the 4-byte authorization id XOR `55`. Nil for anything but 8 hex chars.
    public static func closeCommand(authorizationID: String) -> Data? {
        guard let id = HexCoding.data(authorizationID), id.count == 4 else { return nil }
        return Data([0xAC] + id.map { $0 ^ 0x55 })
    }

    public enum ProbeReply: Sendable, Equatable {
        case active
        case idle(machineID: String)
        case unreadable
    }

    public static func classify(_ frame: Data) -> ProbeReply {
        if isActive(frame) { return .active }
        if let id = identity(frame) { return .idle(machineID: id) }
        return .unreadable
    }

    /// What a read-only probe proves about `machineID`. Only an idle identity frame (`55`)
    /// carrying that id proves the controller is this machine's; `A5` (in use) proves nothing.
    public enum IdentityCheck: Sendable, Equatable { case verified, busy, otherMachine, unreadable }
    public static func check(_ frame: Data, machineID: String) -> IdentityCheck {
        switch classify(frame) {
        case .idle(let id): return id == machineID.uppercased() ? .verified : .otherMachine
        case .active: return .busy
        case .unreadable: return .unreadable
        }
    }

    /// Which command a write is, for diagnostics (never the bytes themselves).
    public enum Command: String, Sendable { case probe, authorization, close, other }
    public static func command(_ data: Data) -> Command {
        if data == probeCommand { return .probe }
        if data.count == authorizationLength { return .authorization }
        if data.count == closeCommandLength, data.first == 0xAC { return .close }
        return .other
    }
}

public struct ShowerFrameError: Error, Equatable, Sendable {
    public init() {}
}

/// Reassembles notifications that arrive split or coalesced. Lengths by first byte:
/// `55` → 20, `AA` → 9, `A5` → 1; any other first byte is malformed (never skipped).
public struct ShowerFrameAssembler: Sendable {
    private var pending = Data()
    public static let bufferLimit = 256
    public init() {}

    public var hasPartialFrame: Bool { !pending.isEmpty }

    public mutating func append(_ data: Data) throws -> [Data] {
        pending.append(data)
        guard pending.count <= Self.bufferLimit else { throw ShowerFrameError() }
        var frames: [Data] = []
        while let first = pending.first {
            let length: Int
            switch first {
            case 0x55: length = ShowerFrames.identityFrameLength
            case 0xAA: length = ShowerFrames.ackLength
            case 0xA5: length = 1
            default: throw ShowerFrameError()
            }
            guard pending.count >= length else { break }
            frames.append(Data(pending.prefix(length)))
            pending = Data(pending.dropFirst(length))
        }
        return frames
    }
}
