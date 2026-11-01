import Foundation
import CryptoKit

/// lxt6 request signing, ported as-is from the existing iOS/Android code:
/// `wxcode = k=v*_k=v…` (field order matters), `sign = md5(secret + formEncode(wxcode))` lower hex.
public enum LxtSigning {
    /// The mini-program's `encodeURIComponent` + form conversion: `A–Z a–z 0–9 - . _ *` kept,
    /// space → `+`, every other UTF-8 byte → `%XX` (upper hex), including `~ ! ' ( )`.
    public static func formEncode(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.utf8.count)
        for b in value.utf8 {
            switch b {
            case 65...90, 97...122, 48...57, 45, 46, 95, 42: out.unicodeScalars.append(UnicodeScalar(b))
            case 32: out.append("+")
            default: out += String(format: "%%%02X", b)
            }
        }
        return out
    }

    public static func wxcode(_ fields: [(String, String)]) -> String {
        fields.map { "\($0.0)=\($0.1)" }.joined(separator: "*_")
    }

    public static func signature(secret: String, wxcode: String) -> String {
        Insecure.MD5.hash(data: Data((secret + formEncode(wxcode)).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `wxcode`, `sign`, `sid` (+ `requestType=1` for AECC), each form-encoded, `&`-joined.
    /// Used as the GET query and as the POST form body.
    public static func signedForm(_ fields: [(String, String)], secret: String, sid: String, requestType: Bool = false) -> String {
        let code = wxcode(fields)
        var params = [("wxcode", code), ("sign", signature(secret: secret, wxcode: code)), ("sid", sid)]
        if requestType { params.append(("requestType", "1")) }
        return params.map { formEncode($0.0) + "=" + formEncode($0.1) }.joined(separator: "&")
    }

    /// The authorize/settle fields, in the order the platform expects.
    public static func operationFields(studentId: String, schoolId: String, machineId: String, frame: Data,
                                       typeId: String, version: String, random: String) -> [(String, String)] {
        [("studentId", studentId), ("schoolId", schoolId), ("machineid", machineId.uppercased()),
         ("machinedata", HexCoding.upper(frame)), ("typeId", typeId), ("alleywaytype", "0"),
         ("rand", random), ("version", version)]
    }

    /// Authorize/settle `rand`: 6 of `0-9A-Z` (secure random).
    public static let operationAlphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    /// `getUserMsg` `random`: 6 upper hex digits (the old code took a UUID prefix).
    public static let userMsgAlphabet = "0123456789ABCDEF"

    public static func random(_ alphabet: String, count: Int = 6) -> String {
        var g = SystemRandomNumberGenerator()
        let chars = Array(alphabet)
        return String((0..<count).map { _ in chars[Int.random(in: 0..<chars.count, using: &g)] })
    }

    public static func isValidOperationRandom(_ s: String) -> Bool {
        s.utf8.count == 6 && s.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) }
    }
}
