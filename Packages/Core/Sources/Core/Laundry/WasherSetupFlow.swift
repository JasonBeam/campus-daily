import Foundation

/// 「扫描机身二维码」 and 「从照片识别」 on the common-washer page. Signed out of U净 they still
/// answer a tap: the U净 login opens first, and once it goes through the tapped one opens.
public enum WasherSetupFlow {
    /// How a machine is added.
    public enum Method: Sendable, Equatable { case scan, photo }

    public enum Tap: Sendable, Equatable {
        case open(Method)
        /// The U净 login, remembering what to open after it.
        case signIn(then: Method)
    }

    public static func tap(_ method: Method, signedIn: Bool) -> Tap {
        signedIn ? .open(method) : .signIn(then: method)
    }

    /// Greyed only while an order is open or a step runs (`mayImport`), or a photo is read.
    public static func addDisabled(mayImport: Bool, busy: Bool) -> Bool { !mayImport || busy }

    /// The login sheet closed: what to open now. Nothing when it was cancelled or opened from
    /// the guide card.
    public static func afterLogin(pending: Method?, signedIn: Bool) -> Method? {
        signedIn ? pending : nil
    }
}
