import Foundation

/// The first value offered wins; `value()` waits for it.
actor FirstResult<T: Sendable> {
    private var result: T?
    private var waiters: [CheckedContinuation<T, Never>] = []

    func offer(_ value: T) {
        guard result == nil else { return }
        result = value
        for waiter in waiters { waiter.resume(returning: value) }
        waiters = []
    }

    func value() async -> T {
        if let result { return result }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
