import Foundation
import Core

public extension InMemorySecureStore {
    /// One temporary lease file per store: the "processes" sharing a store share it too.
    var leaseFile: LeaseFile { TestLeaseFiles.file(for: self) }
}

enum TestLeaseFiles {
    private final class Entry {
        weak var store: InMemorySecureStore?
        let file: LeaseFile
        init(store: InMemorySecureStore, file: LeaseFile) { self.store = store; self.file = file }
    }

    /// Every lease file of this test run; removed when the run ends.
    private static let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("campus-daily-test-leases-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    nonisolated(unsafe) private static var entries: [ObjectIdentifier: Entry] = [:]
    nonisolated(unsafe) private static var removesFolderAtExit = false
    private static let lock = NSLock()

    static func file(for store: InMemorySecureStore) -> LeaseFile {
        lock.withLock {
            let id = ObjectIdentifier(store)
            if let entry = entries[id] {
                if entry.store === store { return entry.file }
                // A freed store's identifier, reused: its file goes, the new store gets its own.
                try? FileManager.default.removeItem(at: entry.file.url)
            }
            if !removesFolderAtExit {
                removesFolderAtExit = true
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                atexit { try? FileManager.default.removeItem(at: TestLeaseFiles.folder) }
            }
            let file = LeaseFile(url: folder.appendingPathComponent("lease-\(UUID().uuidString)"))
            entries[id] = Entry(store: store, file: file)
            return file
        }
    }
}
