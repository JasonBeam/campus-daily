import Foundation

/// A link being let go stays `retiring` until its disconnect arrives. That callback is the link
/// finishing, never the current step failing, even when the same controller was picked again;
/// a reconnect waits for it first.
public enum ShowerRetiringLink: Sendable, Equatable {
    case retired
    /// The current link dropped: the step that runs fails.
    case lost
    case unrelated

    public static func disconnected(isRetiring: Bool, isCurrent: Bool) -> ShowerRetiringLink {
        if isRetiring { return .retired }
        return isCurrent ? .lost : .unrelated
    }


    /// The wait for the retiring link's disconnect failed with `error`. A timeout on a link that
    /// is already down (`disconnected`: its state now) means only the callback went missing: the
    /// link counts as retired and the reconnect goes on. Anything else ends the connect.
    public static func retiredAfterWait(failedWith error: Error, disconnected: Bool) -> Bool {
        disconnected && (error as? ShowerDeviceError) == .timedOut
    }
}
