import Foundation

/// Keep one read-only refresh alive independently of a SwiftUI refresh control's lifetime.
/// Concurrent entry points join the same work rather than cancelling or duplicating requests.
@MainActor public final class CampusRefreshCoordinator {
    private var running: Task<Void, Never>?
    public init() {}
    public func perform(_ operation: @escaping @MainActor () async -> Void) async {
        if let running { await running.value; return }
        let task = Task { @MainActor in
            await operation()
            running = nil
        }
        running = task
        await task.value
    }
}
