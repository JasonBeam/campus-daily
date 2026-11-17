import Foundation

/// Home's laundry row (暖橙 洗衣) and tile (清爽 洗衣机): which state it is in, what it says and
/// where a tap goes. The not-signed-in and unbound states live here only, for both themes.
enum HomeLaundryCard: Equatable {
    /// U净 not signed in: the tap opens 「登录 U净」.
    case signedOut
    /// Signed in, no machine bound: the tap opens 常用洗衣机 to scan one.
    case unbound
    /// A machine bound: the tap opens the laundry page.
    case bound

    enum Action: Equatable { case ujingLogin, washerSetup, laundry }

    init(_ data: HomeData) {
        self = data.laundryBound ? .bound : data.laundrySignedIn ? .unbound : .signedOut
    }

    static let signIn = "登录 U净"
    static let clearTitle = "洗衣机"
    static let scanToBind = "扫机身上的码来绑定"

    var action: Action {
        switch self {
        case .signedOut: .ujingLogin
        case .unbound: .washerSetup
        case .bound: .laundry
        }
    }

    // MARK: 暖橙

    /// 「洗衣」 until a machine is bound (the bound row names the machine itself).
    var warmTitle: String { "洗衣" }

    /// The subtitle while no machine is bound (nil when bound: the machine's state says it).
    var warmSubtitle: String? {
        switch self {
        case .signedOut: "登录 U净 后就能在这里下单"
        case .unbound: Self.scanToBind
        case .bound: nil
        }
    }

    /// Where the number sits: 「登录 U净 ›」 while signed out, nothing while unbound.
    var warmValue: RowValue? { self == .signedOut ? .action(Self.signIn) : nil }

    /// VoiceOver for the whole row while no machine is bound.
    var warmLabel: String? {
        switch self {
        case .signedOut: "洗衣，还没登录 U净，轻点两下去登录"
        case .unbound: "洗衣，" + Self.scanToBind
        case .bound: nil
        }
    }

    // MARK: 清爽

    /// The tile's description: 「未登录 U净」, 「扫码绑定常用洗衣机」 or the usual machine.
    func clearDetail(machine: String?) -> String {
        switch self {
        case .signedOut: "未登录 U净"
        case .unbound: "扫码绑定常用洗衣机"
        case .bound: "常用 · \(machine ?? "")号"
        }
    }

    /// The tile's status line while no machine is bound: 「登录 U净」 in the accent colour.
    var clearValue: RowValue? { self == .signedOut ? .action(Self.signIn) : nil }
}
