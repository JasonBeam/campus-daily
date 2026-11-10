import Foundation

extension LaundryEngineError {
    /// What the laundry page says when a step stops on this.
    public var message: String {
        switch self {
        case .busy: return "正在处理上一步，稍等一下。"
        case .notAllowed: return "现在不能这样操作，下拉刷新看看。"
        case .washerChanged: return "机器或价格变了，刷新一下再下单。"
        case .storage: return "这台手机暂时存不了洗衣订单，重启 App 后再试。"
        }
    }

    /// What the U净 login says when it stops on this. `.storage`: the order record can't be
    /// read, so whose order is open is unknown; nothing clears that before the app restarts.
    public var loginMessage: String {
        self == .storage ? "这台手机现在存不了洗衣订单，重启 App 再登录 U净。" : message
    }
}
