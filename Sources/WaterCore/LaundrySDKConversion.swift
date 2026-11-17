import Foundation

public struct LaundrySDKResult: Equatable, Sendable {
    public let status: String
    public let memo: String
    public init(_ values: [AnyHashable:Any]?) {
        func text(_ key: String) -> String? { (values?[key] as? String) ?? (values?[key] as? NSNumber)?.stringValue }
        status = text("resultStatus") ?? text("resultCode") ?? "unknown"
        memo = text("memo") ?? ""
    }
}

/// A rejected conversion must not deliver SDK results into the external checkout flow.
@MainActor public final class LaundrySDKConversion {
    private enum Decision { case pending, converted, external }
    private var decision = Decision.pending
    private var buffered: (String, String)?
    private var delivered = false
    private let callback: @MainActor (String, String) -> Void

    public init(callback: @escaping @MainActor (String, String) -> Void) { self.callback = callback }

    public func resolve(converted: Bool) {
        guard decision == .pending else { return }
        decision = converted ? .converted : .external
        if converted, let buffered { deliver(buffered.0,buffered.1) }
        buffered = nil
    }

    public func receive(status: String, memo: String) {
        switch decision {
        case .pending: if buffered == nil { buffered = (status,memo) }
        case .converted: deliver(status,memo)
        case .external: break
        }
    }

    private func deliver(_ status: String, _ memo: String) {
        guard !delivered else { return }
        delivered = true; callback(status,memo)
    }
}
