//
//  ShowerBinding.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

// MARK: - Hot-water identity and binding

/// `getUserMsg` answer: the student's identity on the hot-water platform.
public struct ShowerUser: Sendable, Equatable, Codable, CustomStringConvertible {
    public var studentId: String
    public var schoolId: String
    public init(studentId: String, schoolId: String) { self.studentId = studentId; self.schoolId = schoolId }
    public var description: String { "WaterUser(<redacted>, schoolId: \(schoolId))" }
}

/// A node of the hot-water area tree (campus → building → floor → room).
public struct AreaNode: Sendable, Equatable, Hashable, Codable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// One controller from `getMachineMacAddress` (`machineId` is 4 bytes hex, upper-cased).
public struct ShowerMachine: Sendable, Equatable, Hashable, Codable {
    public var machineId: String
    public var name: String
    public var mac: String
    public init(machineId: String, name: String, mac: String) {
        self.machineId = machineId.uppercased(); self.name = name; self.mac = mac
    }
}

/// Keychain `water.binding`: who showers where.
public struct ShowerBinding: Sendable, Equatable, Codable, CustomStringConvertible {
    public var studentId: String
    public var schoolId: String
    public var machineId: String
    public var roomId: String
    public var roomLabel: String
    public var machineName: String?
    /// CoreBluetooth identifier of the controller last verified by its identity frame.
    public var peripheralID: String?
    /// When a start (or the manual 核对) first read this machine's own number from the controller.
    /// Only chooses words (the first start says 「正在核对水控」 and may explain itself): every
    /// start still reads the number before it asks for anything (`ShowerEngine.start`). Nil on
    /// bindings saved before it was kept, and a remembered `peripheralID` never stands in for it.
    public var matchedAt: Date?

    public init(studentId: String, schoolId: String, machineId: String, roomId: String, roomLabel: String,
                machineName: String? = nil, peripheralID: String? = nil, matchedAt: Date? = nil) {
        self.studentId = studentId; self.schoolId = schoolId; self.machineId = machineId.uppercased()
        self.roomId = roomId; self.roomLabel = roomLabel; self.machineName = machineName
        self.peripheralID = peripheralID; self.matchedAt = matchedAt
    }

    /// The same person in the same dorm at the same machine: what a start was tapped for. The
    /// controller remembered for it and the matched marker may change in between.
    public func sameIdentity(_ other: ShowerBinding?) -> Bool {
        guard let other else { return false }
        return studentId == other.studentId && schoolId == other.schoolId && machineId == other.machineId && roomId == other.roomId
    }
    public var description: String { "WaterBinding(<redacted>, room: \(roomLabel))" }

    /// Whether a new binding may be saved now. Not while a shower is open or waiting to be
    /// settled (`mayChange` false: `blocked`), and not while a controller check runs (`busy`):
    /// that check is for the old binding, and its answer would then be shown for the new one.
    public static func checkMayReplace(mayChange: Bool, checking: Bool) throws {
        guard mayChange else { throw ShowerEngineError.blocked }
        guard !checking else { throw ShowerEngineError.busy }
    }
}

/// Persistent ownership gate tying `water.binding` (`water.bindingEpoch`) to `shared.sessionEpoch`
/// so an interrupted account switch or sign-out (killed before UI cleanup writes
/// `PreferenceKey.showerNeedsResidenceReview`) can never authorize a new shower start on cold
/// start, while leaving close/settle of any existing in-flight shower untouched.
public enum ShowerEpochOwnership {
    private static func ownerTag(for epoch: SessionEpoch) -> String {
        epoch.phase == .switching ? "\(epoch.id):switching" : epoch.id
    }

    /// Records the current `shared.sessionEpoch` as the owner of `water.binding`.
    /// On a legacy install with neither an epoch nor a legacy stale mark, clears `water.bindingEpoch`
    /// so the binding remains valid until the first account switch or sign-out.
    /// Throws when the store cannot be read/written or when a legacy stale mark is present
    /// without a committed epoch.
    public static func recordCurrentOwner(store: SecureStore) throws {
        let epochStore = SessionEpochStore(store: store)
        let currentEpoch = try epochStore.read()
        if let currentEpoch {
            try store.write(Data(ownerTag(for: currentEpoch).utf8), for: .showerBindingEpoch)
            return
        }
        if try epochStore.hasLegacyStaleMark() {
            throw StorageError(operation: "write \(StoreKey.showerBindingEpoch.rawValue)", status: -1)
        }
        try store.delete(.showerBindingEpoch)
    }

    /// Returns `true` when `binding` is present and cannot be confirmed to belong to the current
    /// school session epoch (fail-closed on Keychain read error, undecodable epoch, legacy stale
    /// mark, epoch ID mismatch, or `.switching` recovery into `.signedOut` — including after an
    /// account switch or sign-out whose UI cleanup was interrupted by a crash/kill).
    public static func needsReview(binding: ShowerBinding?, store: SecureStore) -> Bool {
        guard binding != nil else { return false }
        let epochStore = SessionEpochStore(store: store)
        let currentEpoch: SessionEpoch?
        let hasLegacyStale: Bool
        let bindingEpoch: String?
        do {
            currentEpoch = try epochStore.read()
            hasLegacyStale = currentEpoch == nil ? try epochStore.hasLegacyStaleMark() : false
            if let raw = try store.read(.showerBindingEpoch) {
                guard let id = String(data: raw, encoding: .utf8), !id.isEmpty else { return true }
                bindingEpoch = id
            } else {
                bindingEpoch = nil
            }
        } catch {
            return true
        }
        if let currentEpoch {
            return bindingEpoch != ownerTag(for: currentEpoch)
        }
        if hasLegacyStale { return true }
        return bindingEpoch != nil
    }
}

// MARK: - Authorize / settle results

/// `bathingConsumptionAuthorization` reply: the 15-byte frame to write to the controller and
/// the 4-byte authorization id (the reply's `studentId`) the close command is built from.
public struct ShowerAuthorization: Sendable, Equatable, CustomStringConvertible {
    public var machineID: String
    public var payload: Data
    public var authorizationID: String
    public init(machineID: String, payload: Data, authorizationID: String) {
        self.machineID = machineID; self.payload = payload; self.authorizationID = authorizationID
    }
    public var description: String { "WaterAuthorization(<redacted>, payload: \(payload.count) bytes)" }
}

/// `analysisOfBathingConsumptionData` reply. `amount` is nil when the server's `pay` is
/// missing or not a whole number of fen: never shown as ¥0.
public struct ShowerReceipt: Sendable, Equatable, Codable {
    public var amount: Money?
    public init(amount: Money?) { self.amount = amount }

    public static let maxFen: Int64 = 100_000_000_000

    /// The original pay page renders `pay / 100` yuan; `pay` is fen as a number or digit string.
    public static func parse(pay value: JSONValue?) -> ShowerReceipt {
        let fen: Int64?
        switch value {
        case .int(let i)?: fen = i
        case .double(let d)?: fen = (d.rounded() == d && abs(d) < 1e15) ? Int64(d) : nil
        case .string(let s)?:
            fen = s.range(of: "^[0-9]+$", options: .regularExpression) != nil ? Int64(s) : nil
        default: fen = nil
        }
        guard let fen, fen >= 0, fen <= maxFen else { return ShowerReceipt(amount: nil) }
        return ShowerReceipt(amount: Money(fen: Int(fen)))
    }
}

// MARK: - Hex

/// Strict hex helpers (no whitespace, even length).
public enum HexCoding {
    public static func data(_ text: String) -> Data? {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty, bytes.count % 2 == 0 else { return nil }
        func nibble(_ b: UInt8) -> UInt8? {
            switch b {
            case 48...57: return b - 48
            case 65...70: return b - 55
            case 97...102: return b - 87
            default: return nil
            }
        }
        var out = Data(capacity: bytes.count / 2)
        for i in stride(from: 0, to: bytes.count, by: 2) {
            guard let a = nibble(bytes[i]), let b = nibble(bytes[i + 1]) else { return nil }
            out.append(a << 4 | b)
        }
        return out
    }

    public static func upper(_ data: Data) -> String {
        let digits = Array("0123456789ABCDEF".utf8)
        var out = [UInt8]()
        out.reserveCapacity(data.count * 2)
        for b in data { out.append(digits[Int(b >> 4)]); out.append(digits[Int(b & 0x0F)]) }
        return String(decoding: out, as: UTF8.self)
    }

    /// True for exactly `bytes` bytes of hex.
    public static func isHex(_ text: String, bytes: Int) -> Bool {
        text.utf8.count == bytes * 2 && data(text) != nil
    }
}
