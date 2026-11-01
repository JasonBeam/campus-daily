import Foundation

/// Storage failure. Session stores fail closed: the side effect after a failed write does not run.
public struct StorageError: Error, Equatable, Sendable {
    public var operation: String
    public var status: Int32
    public init(operation: String, status: Int32) { self.operation = operation; self.status = status }
}
