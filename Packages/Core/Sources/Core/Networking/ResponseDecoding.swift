import Foundation

/// Shared response handling for JSON services.
public enum ResponseDecoding {
    /// - 401/403 → `sessionExpired(service)`
    /// - other non-2xx → `rejected(service, "HTTP <status>", "")`
    /// - empty body → `nil` (the caller decides: ecykt maps it to `badRequest`)
    /// - not JSON → `malformed(service, "$")`
    /// - a JSON string that itself holds an object/array is unwrapped (lxt6 errors)
    public static func json(_ response: HTTPResponse, service: Service) throws -> JSONValue? {
        if response.status == 401 || response.status == 403 { throw ServiceError.sessionExpired(service) }
        guard (200..<300).contains(response.status) else {
            throw ServiceError.rejected(service, code: "HTTP \(response.status)", message: "")
        }
        if response.isBodyEmpty { return nil }
        guard var value = try? JSONValue.parse(response.body) else { throw ServiceError.malformed(service, "$") }
        if case .string(let s) = value, let inner = try? JSONValue.parse(s), inner.object != nil || inner.array != nil {
            value = inner
        }
        return value
    }

    /// Reads an envelope field accepting `code`/`Code`, `msg`/`message`/`Message`, `data`/`Data`.
    public static func code(_ root: JSONValue) -> String? { (root["code"] ?? root["Code"])?.text }

    public static func message(_ root: JSONValue) -> String {
        (root["msg"] ?? root["message"] ?? root["Message"])?.text ?? ""
    }

    public static func data(_ root: JSONValue) -> JSONValue? { root["data"] ?? root["Data"] }
}
