import Foundation

/// The lock around state the app shares with its extensions (the App Group's preferences, its
/// files): what runs in `body` is one read-compare-write the other process can't land in the
/// middle of. In the app it is the refresh lease file's `flock` (`RefreshLease`). A lock that
/// can't be taken throws, and `body` does not run.
public protocol SharedLock: Sendable {
    func locked<T>(_ body: () throws -> T) throws -> T
}
