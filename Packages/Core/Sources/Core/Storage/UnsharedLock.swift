import Foundation

/// `SharedLock` for state no other process reads (tests, previews): `body` just runs.
public struct UnsharedLock: SharedLock {
    public init() {}
    public func locked<T>(_ body: () throws -> T) throws -> T { try body() }
}
