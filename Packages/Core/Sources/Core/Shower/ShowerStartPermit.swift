import Foundation
import os

/// One explicit 开始洗澡 (a tap, a Siri request) may send one authorize request, and only while
/// nothing took the tap back (`ShowerEngine.start(_:permit:)`). The app revokes it the moment the
/// account, the dorm or the tap itself no longer holds (退出登录, an account switch, a new
/// binding, the app sent to the background); the engine consumes it right before the request
/// leaves. Both happen under one lock and nothing waits under it, so exactly one of them wins:
/// revoked first, nothing is sent; consumed first, the request may have left and the record is
/// kept by the usual rules (never cleared, never sent again).
public final class ShowerStartPermit: Sendable {
    enum State: Sendable { case open, revoked, consumed }
    private let state = OSAllocatedUnfairLock(initialState: State.open)

    public init() {}

    /// Takes the tap back. True when nothing was sent with it (it was still open, or already
    /// revoked); false once it was consumed: the request may have left.
    @discardableResult public func revoke() -> Bool {
        state.withLock { current in
            switch current {
            case .open, .revoked: current = .revoked; return true
            case .consumed: return false
            }
        }
    }

    /// The authorize request is about to leave. True exactly once, and only while open: never
    /// after a revoke, never a second time.
    public func consume() -> Bool {
        state.withLock { current in
            guard current == .open else { return false }
            current = .consumed
            return true
        }
    }

    /// Neither revoked nor consumed. A look only: it never decides a send (`consume` does).
    public var isOpen: Bool { state.withLock { $0 == .open } }
}
