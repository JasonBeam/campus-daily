import Foundation

extension LaundryStartLine {
    /// 清爽's line for `c`: the same states as `make` (暖橙's), in the original app's words, one
    /// sentence each. Nil for normal orders and once washing.
    public static func clear(_ c: LaundryCheckout) -> LaundryStartLine? {
        guard let line = make(c) else { return nil }
        let text: String
        switch line.kind {
        case .armed: text = "付款后请返回校日常，核对已付款后自动发送启动指令。超过下单后10分钟请在U净手动启动。"
        case .checking: text = "正在核对订单…"
        case .ready: text = "已付款，正在发送启动指令"
        case .sent: text = "启动指令已提交，等待机器响应；若未启动请到U净核对"
        case .uncertain: text = "启动指令结果待核对，不会重复发送；请到U净核对"
        case .refused:
            guard case .refused(let message, _)? = c.start else { return nil }
            let words = message.trimmingCharacters(in: .whitespacesAndNewlines)
            text = words.isEmpty ? "U净未接受启动指令；请在U净手动启动" : "U净未接受启动指令：\(words)；请在U净手动启动"
        case .blocked:
            guard case .blocked(let reason)? = c.start else { return nil }
            switch reason {
            case .expired: text = "本单自动启动已过期，请在U净核对后手动启动"
            case .account: text = "本单不属于当前U净账号，未自动启动；请在对应账号的U净中启动"
            case .price: text = "本单金额与确认时不一致，未自动启动；请在U净核对后手动启动"
            case .unsupported, .offline, .selfClean, .dispenser: text = "这台机器需在U净完成启动前检查，请使用官方订单"
            }
        }
        return LaundryStartLine(kind: line.kind, text: text)
    }
}
