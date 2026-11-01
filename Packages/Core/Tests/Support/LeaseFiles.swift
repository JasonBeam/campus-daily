import Foundation
import Core

public extension InMemorySecureStore {
    /// One temporary lease file per store: the "processes" sharing a store share it too.
    var leaseFile: LeaseFile { TestLeaseFiles.file(for: self) }
}

enum TestLeaseFiles {
    // The stores are kept so their identifiers are never reused for another store.
    nonisolated(unsafe) private static var files: [ObjectIdentifier: (InMemorySecureStore, LeaseFile)] = [:]
    private static let lock = NSLock()

    static func file(for store: InMemorySecureStore) -> LeaseFile {
        lock.withLock {
            if let (_, file) = files[ObjectIdentifier(store)] { return file }
            let file = LeaseFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("lease-\(UUID().uuidString)"))
            files[ObjectIdentifier(store)] = (store, file)
            return file
        }
    }
}
