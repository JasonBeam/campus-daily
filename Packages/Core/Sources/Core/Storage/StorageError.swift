import Foundation

/// Storage failure. Session stores fail closed: the side effect after a failed write does not run.
public struct StorageError: Error, Equatable, Sendable {
    public var operation: String
    public var status: Int32
    public init(operation: String, status: Int32) { self.operation = operation; self.status = status }

    /// The item was read and its contents no longer decode (damaged, or an older shape).
    public static func undecodable(_ item: String) -> StorageError { StorageError(operation: "decode \(item)", status: -1) }

    /// `undecodable`: reading it again won't help. Any other read error is the store refusing
    /// (an `errSec…` status).
    public var isUndecodable: Bool { operation.hasPrefix("decode ") }
}
