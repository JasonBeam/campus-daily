import Foundation
import CryptoKit

public enum WaterProtocol {
    public static let service = "FFE0"
    public static let notify = "FFE1"
    public static let write = "FFE2"
    public static func identity(_ frame: Data) throws -> String {
        guard frame.count == 20, frame.first == 0x55 else { throw WaterError.malformedFrame }
        return Data(frame.dropFirst().prefix(4)).upperHex
    }
    public static func closeCommand(_ authorizationID: String) throws -> Data {
        guard let id = Data(strictHex: authorizationID), id.count == 4 else { throw WaterError.malformedFrame }
        return Data([0xAC] + id.map { $0 ^ 0x55 })
    }
    // Exact mini-program encodeURIComponent + form conversion, including escaped ~.
    public static func encodeForm(_ value: String) -> String {
        value.utf8.map { b in
            switch b {
            case 65...90, 97...122, 48...57, 45, 46, 95, 42: return String(UnicodeScalar(b))
            case 32: return "+"
            default: return String(format: "%%%02X", b)
            }
        }.joined()
    }
    public static func signature(secret: String, wxcode: String) -> String {
        Insecure.MD5.hash(data: Data((secret + encodeForm(wxcode)).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    public static func wxcode(config: WaterConfig, frame: Data, random: String) throws -> String {
        try config.validate()
        guard try identity(frame) == config.machineID.uppercased() else { throw WaterError.wrongDevice }
        guard random.count == 6, random.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
            throw WaterError.invalidConfig
        }
        return [("studentId",config.studentID),("schoolId",config.schoolID),
                ("machineid",config.machineID.uppercased()),("machinedata",frame.upperHex),
                ("typeId",String(config.typeID)),("alleywaytype","0"),
                ("rand",random),("version",String(config.version))]
            .map { "\($0.0)=\($0.1)" }.joined(separator: "*_")
    }
}

// Parses split and coalesced notifications; never guesses away malformed bytes.
public struct FrameDecoder {
    private var pending = Data()
    public init() {}
    public var hasPartialFrame: Bool { !pending.isEmpty }
    public mutating func append(_ data: Data) throws -> [Data] {
        pending.append(data)
        guard pending.count <= 256 else { throw WaterError.malformedFrame }
        var frames: [Data] = []
        while let first = pending.first {
            let length: Int
            switch first { case 0x55: length = 20; case 0xAA: length = 9; case 0xA5: length = 1
            default: throw WaterError.malformedFrame }
            guard pending.count >= length else { break }
            frames.append(Data(pending.prefix(length)))
            pending.removeFirst(length)
        }
        return frames
    }
}
