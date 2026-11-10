import Foundation

/// What the controller notifies on the kept link, decided without CoreBluetooth. Only a reply
/// inside an exchange (a write we sent) counts: a notification while nothing was asked is
/// dropped, so it can neither become the next command's reply nor block it.
public struct ShowerNotifyChannel: Sendable {
    public enum Received: Sendable, Equatable {
        /// Outside an exchange: nothing kept.
        case ignored
        /// Part of a frame; the rest is still to come.
        case partial
        /// The reply is complete (`take`).
        case frame
        /// The reply can't be read; the channel stays blocked until `reset`.
        case failed(ShowerDeviceError)
    }

    private var assembler = ShowerFrameAssembler()
    private var frame: Data?
    private var error: ShowerDeviceError?

    public init() {}

    /// A new or reused link starts clean.
    public mutating func reset() { self = ShowerNotifyChannel() }

    /// Why the next write can't start: an earlier reply failed, or one is half or still unread.
    /// Nil when it may.
    public var blocker: ShowerDeviceError? {
        if let error { return error }
        return assembler.hasPartialFrame || frame != nil ? .disconnected : nil
    }

    /// `value` nil or `failed`: CoreBluetooth reported an error for the notification.
    public mutating func receive(_ value: Data?, failed: Bool, inExchange: Bool) -> Received {
        guard inExchange else { return .ignored }
        guard !failed, let value else { error = .disconnected; return .failed(.disconnected) }
        do {
            let frames = try assembler.append(value)
            guard frames.count <= 1, frame == nil else { throw ShowerFrameError() }
            if let first = frames.first { frame = first; return .frame }
            return .partial
        } catch {
            self.error = .malformedFrame
            return .failed(.malformedFrame)
        }
    }

    /// A complete reply waits to be taken.
    public var hasFrame: Bool { frame != nil }

    /// The complete reply, once.
    public mutating func take() -> Data? {
        defer { frame = nil }
        return frame
    }
}
