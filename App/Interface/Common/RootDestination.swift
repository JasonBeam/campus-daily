import Foundation

/// Where a root was last asked to go: a widget link, or the login step after the sample. Some
/// of those wait for a closing sheet first; a newer request supersedes one still waiting, so the
/// newest wins. The waiting step is cancelled, and should it still wake, it does nothing.
@MainActor final class RootDestination {
    private var generation = 0
    private var waiting: Task<Void, Never>?

    /// A new destination: what an older one still waits to do is dropped.
    func supersede() {
        generation += 1
        waiting?.cancel()
        waiting = nil
    }

    /// A new destination, reached after `ms` (a closing sheet goes first) unless a newer one
    /// is asked for in the meantime.
    func after(_ ms: Int, _ step: @escaping @MainActor () -> Void) {
        supersede()
        let mine = generation
        waiting = Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(ms)) } catch { return }
            guard let self, !Task.isCancelled, generation == mine else { return }
            waiting = nil
            step()
        }
    }
}
