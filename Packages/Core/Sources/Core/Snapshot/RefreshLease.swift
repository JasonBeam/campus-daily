import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The cross-process lock around a school refresh. The app and the widget are two processes
/// sharing one stored card session; only the holder of this lease refreshes (and so mints or
/// rotates the session). The lease is one small file `{owner, expiresAt}` in the App Group
/// container both processes can open. Every step (take, renew, check, give back, clear) is one
/// read-compare-write done while holding an exclusive `flock` on that file, so two processes can
/// never both find the same lease free, and a holder whose lease ran out can never write over
/// the next one's. The lock is held only for that step, never across an `await`: iOS ends a
/// suspended process that still holds a file lock in a shared container.
///
/// A holder that dies leaves its lease to expire after `duration`; the next process takes it.
/// Without the shared container (a build signed without the App Group) the app keeps the lease
/// in its own container (`appFile`), so its own reads and logins still take turns; the widget's
/// `file` is nil and its lease can never be taken, so it leaves every read to the app.
public struct RefreshLease: Sendable {
    struct Record: Codable, Equatable {
        var owner: String
        var expiresAt: Date
    }

    /// The lease file in the shared container, or nil when this build has no App Group (none it
    /// is entitled to, under the Info.plist name or its own bundle id: `AppIdentity.usableAppGroup`).
    public static func sharedFile(appGroup: String? = AppIdentity.usableAppGroup) -> LeaseFile? {
        appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            .map { LeaseFile(url: $0.appendingPathComponent("refresh.lease")) }
    }

    /// The app's lease file: the shared one, or, in a build without the App Group, one in the
    /// app's own container (`ownContainer`, Application Support; created when missing). The widget
    /// can't open that one, so it never reads (`sharedFile` is nil there too), while the app's own
    /// reads, logins, recharge and hand-off still take turns: `flock` on separate descriptors
    /// excludes within one process as well. That file is created here and excluded from backup
    /// (a restore must not bring a lease back). nil only when neither can be used.
    public static func appFile(appGroup: String? = AppIdentity.usableAppGroup,
                               ownContainer: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first) -> LeaseFile? {
        if let shared = sharedFile(appGroup: appGroup) { return shared }
        guard let ownContainer,
              (try? FileManager.default.createDirectory(at: ownContainer, withIntermediateDirectories: true)) != nil
        else { return nil }
        var url = ownContainer.appendingPathComponent("refresh.lease")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return LeaseFile(url: url)
    }

    let file: LeaseFile?
    /// Random per refresher (process): `app-<uuid>` / `widget-<uuid>`. Nothing personal.
    public let owner: String
    let now: @Sendable () -> Date
    public let duration: TimeInterval

    /// Longer than the slowest refresh chain: liveness, portal exchange, one password login and
    /// the exchange after it, each up to 20 s on a slow network, plus the reads (60–180 s).
    public static let defaultDuration: TimeInterval = 180
    /// The holder pushes the expiry forward this often while its read runs.
    public static let renewInterval: TimeInterval = 20

    public init(file: LeaseFile?, owner: String, duration: TimeInterval = RefreshLease.defaultDuration,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.file = file; self.owner = owner; self.duration = duration; self.now = now
    }

    /// The same file under another owner (a login from the app's form beside its own refresh).
    func with(owner: String) -> RefreshLease { RefreshLease(file: file, owner: owner, duration: duration, now: now) }

    /// A new owner id for one process: the role plus a random UUID.
    public static func owner(_ role: String) -> String { role + "-" + UUID().uuidString }

    /// False when there is no shared file to lock: nobody can take the lease.
    public var isAvailable: Bool { file != nil }

    /// Takes the lease when nobody holds it, or when the holder's lease has run out (an
    /// owner whose own lease ran out takes it afresh like anyone else). False while another
    /// owner holds a live lease, or when the file can't be opened, read or written (a locked
    /// phone before the first unlock): no lease, no refresh.
    public func acquire() -> Bool {
        update { current in
            if let holder = current, holder.owner != owner, !isStale(holder) { return (current, false) }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), true)
        } ?? false
    }

    /// Still ours and not run out: push the expiry forward. False = lost (it ran out, another
    /// process took it, or a sign-out removed it): stop before minting, logging in or writing a
    /// credential. Nothing is written then.
    public func renew() -> Bool {
        update { current in
            guard let holder = current, holder.owner == owner, holder.expiresAt > now() else { return (current, false) }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), true)
        } ?? false
    }

    /// One locked step for a write-back: while this owner still holds a live lease, its expiry
    /// is pushed forward and `body` runs inside the same lock, so the other process can neither
    /// take the lease nor clear it between the check and what `body` compares and writes. nil =
    /// not ours any more (ran out, taken, removed by a sign-out) or no usable file: `body` did not
    /// run. Once `body` ran its result is returned even when the pushed-forward expiry could not
    /// be stored afterwards: the write happened, and the lease stays ours until its old expiry
    /// (the next renewal finds out). `body` is synchronous and short (a Keychain or snapshot
    /// write); no `await` can run inside the lock. What `body` throws is rethrown.
    public func withOwnership<T>(_ body: () throws -> T) throws -> T? {
        var ran: Result<T, Error>?
        _ = update { current -> (Record?, Void) in
            guard let holder = current, holder.owner == owner, holder.expiresAt > now() else { return (current, ()) }
            ran = Result { try body() }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), ())
        }
        return try ran?.get()
    }

    /// `withOwnership` for the one write that may follow a lease which only ran out: this owner
    /// is still the stored one (nobody took the lease since, and no sign-out removed it), so
    /// nobody else wrote a credential meanwhile: every credential writer needs the lease and a
    /// sign-out removes it first. The lease is taken again (expiry pushed forward) and `body`
    /// runs, in the same locked step. nil = another owner, no lease, or no usable file.
    func withOwnershipRetaking<T>(_ body: () throws -> T) throws -> T? {
        var ran: Result<T, Error>?
        _ = update { current -> (Record?, Void) in
            guard let holder = current, holder.owner == owner else { return (current, ()) }
            ran = Result { try body() }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), ())
        }
        return try ran?.get()
    }

    /// `body` inside the file's lock, whoever holds the lease; the lease itself is left as it is.
    /// For a write that needs no lease of its own but must not land between another owner's
    /// compare and write (保存密码 off). Only a lease with no file at all (a build with no
    /// container for it) runs `body` as it is. A file that can't be opened, locked or read
    /// (protected before the first unlock) throws that error and `body` does not run: unlocked,
    /// it could land between the other process's compare and write. What `body` throws is
    /// rethrown; once `body` ran, its result stands even if the file could not be written after.
    public func locked<T>(_ body: () throws -> T) throws -> T {
        guard let file else { return try body() }
        var ran: Result<T, Error>?
        do {
            _ = try file.update { current -> (RefreshLease.Record?, Void) in
                ran = Result { try body() }
                return (current, ())
            }
        } catch {
            guard ran != nil else { throw error }
        }
        guard let ran else { throw LeaseFile.Failure(step: "lock", code: EIO) }
        return try ran.get()
    }

    /// `acquire()` without waiting for the lock: false while another step holds it. Tests use it
    /// as the other process trying at one exact moment.
    func tryAcquire() -> Bool {
        update(waiting: false) { current in
            if let holder = current, holder.owner != owner, !isStale(holder) { return (current, false) }
            return (Record(owner: owner, expiresAt: now().addingTimeInterval(duration)), true)
        } ?? false
    }

    /// `clear()` without waiting for the lock: false while another step holds it (tests: the
    /// other process's sign-out trying at one exact moment).
    func tryClear() -> Bool {
        guard let file else { return false }
        return (try? file.update(waiting: false) { _ in (nil, true) }) ?? false
    }

    /// Still ours (not taken over, not removed by a sign-out in the other process).
    public func holds() -> Bool {
        update { current in (current, current?.owner == owner) } ?? false
    }

    /// Sign-out and reset: the lease goes, whoever holds it.
    public func clear() throws {
        guard let file else { return }
        _ = try file.update { _ in (nil, ()) }
    }

    /// Gives the lease back if it is still ours.
    public func release() {
        _ = update { current in current?.owner == owner ? (nil, ()) : (current, ()) }
    }

    /// Run out, or set further ahead than any holder would (a clock moved back): either way
    /// nobody is using it.
    func isStale(_ record: Record) -> Bool {
        let t = now()
        return record.expiresAt <= t || record.expiresAt > t.addingTimeInterval(duration * 2)
    }

    /// The stored lease (for tests and diagnostics).
    func read() throws -> Record? {
        guard let file else { return nil }
        return try file.update { current in (current, current) }
    }

    /// One locked read-compare-write; nil when the file can't be used.
    private func update<T>(waiting: Bool = true, _ body: (Record?) -> (Record?, T)) -> T? {
        guard let file else { return nil }
        return try? file.update(waiting: waiting, body)
    }
}

/// The lease file's lock guards the other shared state too (the App Group's preferences):
/// `locked` runs a step whoever holds the lease.
extension RefreshLease: SharedLock {}

/// The lease's file: `update` reads the record, lets the caller decide, and writes the
/// decision back, all under one exclusive `flock`. An empty file is "no lease"; an unreadable
/// one counts as long expired, so it can't block refreshes forever.
public struct LeaseFile: Sendable {
    public let url: URL
    /// Runs inside the lock right after the record was read (tests use it to let the other
    /// "process" try at exactly that moment).
    let insideLock: (@Sendable () -> Void)?
    /// Every changed record fails to be written (tests: a full or broken container).
    let failsWrites: Bool

    public init(url: URL) { self.init(url: url, insideLock: nil) }

    init(url: URL, insideLock: (@Sendable () -> Void)?, failsWrites: Bool = false) {
        self.url = url; self.insideLock = insideLock; self.failsWrites = failsWrites
    }

    struct Failure: Error { let step: String; let code: Int32 }

    /// The stored owner, run out or not (nil = no lease). Read by the tests only.
    func storedOwner() -> String? { ((try? update { ($0, $0?.owner) }) ?? nil) }

    func update<T>(waiting: Bool = true, _ body: (RefreshLease.Record?) -> (RefreshLease.Record?, T)) throws -> T {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure(step: "open", code: errno) }
        defer { close(fd) }
        while flock(fd, waiting ? LOCK_EX : LOCK_EX | LOCK_NB) != 0 {
            guard errno == EINTR else { throw Failure(step: "lock", code: errno) }
        }
        defer { flock(fd, LOCK_UN) }
        let before = try readAll(fd)
        let current: RefreshLease.Record? = before.isEmpty ? nil
            : (try? JSONDecoder().decode(RefreshLease.Record.self, from: before)) ?? RefreshLease.Record(owner: "", expiresAt: .distantPast)
        insideLock?()
        let (next, result) = body(current)
        let after = try next.map { try JSONEncoder().encode($0) } ?? Data()
        if after != before {
            if failsWrites { throw Failure(step: "write", code: EIO) }
            try writeAll(fd, after)
        }
        return result
    }

    private func readAll(_ fd: Int32) throws -> Data {
        guard lseek(fd, 0, SEEK_SET) == 0 else { throw Failure(step: "seek", code: errno) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { if errno == EINTR { continue }; throw Failure(step: "read", code: errno) }
            if n == 0 { return data }
            data.append(buffer, count: n)
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) throws {
        guard ftruncate(fd, 0) == 0 else { throw Failure(step: "truncate", code: errno) }
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, off_t(offset)) }
            if n < 0 { if errno == EINTR { continue }; throw Failure(step: "write", code: errno) }
            offset += n
        }
    }
}

/// Handed to a credential or snapshot write-back that runs under the refresh lease: the write
/// happens in one locked step with the check that the lease is still ours
/// (`RefreshLease.withOwnership`). Without a lease (tests, previews, an app with no container
/// for its lease file) it just runs.
public struct LeaseOwnership: Sendable {
    let lease: RefreshLease?

    public init(_ lease: RefreshLease?) { self.lease = lease }

    public static let unchecked = LeaseOwnership(nil)

    /// nil = the lease is not ours any more, or the task was cancelled (the widget past its
    /// deadline, about to be suspended: it must not take the file lock now); `body` did not run.
    public func write<T>(_ body: () throws -> T) throws -> T? {
        guard let lease else { return try body() }
        guard !Task.isCancelled else { return nil }
        return try lease.withOwnership(body)
    }

    /// `write` for a password login's accepted portal token and the saved account's hold and
    /// pause only: the lease may have run out
    /// while this owner is still the stored one (`RefreshLease.withOwnershipRetaking`). The owner
    /// check stays, and so does the cancellation check: a cancelled task (the widget past its
    /// deadline, about to be suspended) must not take the file lock, so nothing is written.
    func writeRetaking<T>(_ body: () throws -> T) throws -> T? {
        guard let lease else { return try body() }
        guard !Task.isCancelled else { return nil }
        return try lease.withOwnershipRetaking(body)
    }
}
