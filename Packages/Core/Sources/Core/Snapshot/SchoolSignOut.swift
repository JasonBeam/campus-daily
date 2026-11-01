import Foundation

/// 退出登录 and the reset's sign-out, in order: the refresh lease first (a read in the other
/// process stops before writing a credential back), then every school item, then the widget
/// snapshot. Sign-outs run one after another, and a sign-in, a web sign-in or a saved password
/// first awaits `finished()`, so it starts only once every sign-out asked for before it has
/// finished: the sign-out still waiting for the lease's file lock can't delete the session the
/// sign-in just stored.
public final class SchoolSignOut: @unchecked Sendable {
    // @unchecked: `last` is touched only under `lock`.
    let session: SchoolSession
    let refresher: SnapshotRefresher
    private let lock = NSLock()
    private var last: Task<Bool, Never>?

    public init(session: SchoolSession, refresher: SnapshotRefresher) {
        self.session = session; self.refresher = refresher
    }

    /// Starts a sign-out at once (after any still running). Its value: true when everything was
    /// deleted, false when something is still stored (退出登录 can be tried again).
    @discardableResult public func start() -> Task<Bool, Never> {
        lock.withLock {
            let before = last, session = session, refresher = refresher
            let task = Task {
                _ = await before?.value
                await refresher.revokeLease()
                var deleted = true
                do { try await session.signOut() } catch { deleted = false }
                do { try await refresher.clear() } catch { deleted = false }
                return deleted
            }
            last = task
            return task
        }
    }

    /// Returns once every sign-out started before this call has finished.
    public func finished() async {
        let pending = lock.withLock { last }
        _ = await pending?.value
    }
}
