import Foundation

/// A finite extension of the current payment flow, never a scheduled background job.
@MainActor public protocol LaundryPaymentRuntime: AnyObject {
    func begin(maximumDuration: TimeInterval, expiration: @escaping @MainActor @Sendable () -> Void) -> Bool
    func end()
}

@MainActor public final class LaundryPaymentWatcher {
    public static let maximumDuration: TimeInterval = 45
    private let runtime: any LaundryPaymentRuntime
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private var task: Task<Void, Never>?
    private var generation: UUID?
    public var isRunning: Bool { generation != nil }

    public init(runtime: any LaundryPaymentRuntime,
                sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.runtime = runtime; self.sleep = sleep
    }

    @discardableResult public func start(shouldContinue: @escaping @MainActor () -> Bool,
                                        refresh: @escaping @MainActor () async -> Void) -> Bool {
        stop()
        guard shouldContinue() else { return false }
        let run = UUID(); generation = run
        let granted = runtime.begin(maximumDuration: Self.maximumDuration) { [weak self] in self?.finish(run) }
        guard granted, generation == run else {
            runtime.end()
            if generation == run { generation = nil }
            return false
        }
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.finish(run) }
            while !Task.isCancelled, self.generation == run, shouldContinue() {
                await refresh()
                guard !Task.isCancelled, self.generation == run, shouldContinue() else { return }
                do { try await self.sleep(1) } catch { return }
            }
        }
        return true
    }

    public func stop() {
        guard generation != nil else { return }
        generation = nil
        task?.cancel(); task = nil
        runtime.end()
    }

    private func finish(_ run: UUID) {
        // A cancelled old read may finish after a newer payment window has begun.
        guard generation == run else { return }
        stop()
    }
}
