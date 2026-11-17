import UIKit
import Core

/// The background task behind 立刻洗衣's window (`LaundryPaymentWindow`): asked for right before
/// Alipay opens, it lets the app read the order once a second for at most 45 s while it is out
/// of the front. Refused by iOS: nothing runs and the order waits for the app as before. It ends
/// exactly once (iOS taking it back, the deadline, `tick` saying stop, or `stop()`), and ending
/// it cancels the read in progress rather than waiting for it: that read winds itself down.
@MainActor final class LaundryPaymentWindowRunner {
    struct System {
        /// Begins a background task; nil when iOS refuses. `expired` runs if iOS ends it first.
        var begin: @MainActor (_ expired: @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier?
        var end: @MainActor (UIBackgroundTaskIdentifier) -> Void
        var sleep: @Sendable (TimeInterval) async throws -> Void

        static var live: System {
            System(begin: { expired in
                let id = UIApplication.shared.beginBackgroundTask(withName:"laundry.paymentWindow") {
                    MainActor.assumeIsolated { expired() }
                }
                return id == .invalid ? nil : id
            }, end: { UIApplication.shared.endBackgroundTask($0) },
            sleep: { try await Task.sleep(for:.seconds($0)) })
        }
    }

    nonisolated static let duration = LaundryPaymentWindow.maxDuration

    private let system: System
    private var run: (id: UUID, task: UIBackgroundTaskIdentifier, onStop: @MainActor () -> Void)?
    private var loop: Task<Void, Never>?
    private var deadline: Task<Void, Never>?

    var isActive: Bool { run != nil }

    init(system: System = .live) { self.system = system }

    /// `tick`: one read; false ends the window. `onStop`: once, however it ends. False when iOS
    /// refused or a window already runs (it is never begun twice).
    @discardableResult
    func start(tick: @escaping @MainActor () async -> Bool, onStop: @escaping @MainActor () -> Void) -> Bool {
        guard run == nil else { return false }
        let id = UUID()
        guard let task = system.begin({ [weak self] in self?.stop(id) }) else { return false }
        run = (id, task, onStop)
        let sleep = system.sleep
        // The deadline runs on its own: a read in progress never holds it up.
        deadline = Task { [weak self] in
            do { try await sleep(Self.duration) } catch { return }
            self?.stop(id)
        }
        loop = Task { [weak self] in
            while true {
                do { try await sleep(1) } catch { return }
                guard !Task.isCancelled, self?.run?.id == id else { return }
                guard await tick() else { break }
            }
            self?.stop(id)
        }
        return true
    }

    func stop() {
        if let id = run?.id { stop(id) }
    }

    private func stop(_ id: UUID) {
        guard let current = run, current.id == id else { return }
        run = nil
        loop?.cancel(); loop = nil
        deadline?.cancel(); deadline = nil
        system.end(current.task)
        current.onStop()
    }
}
