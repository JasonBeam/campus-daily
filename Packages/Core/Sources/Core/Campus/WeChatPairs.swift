import Foundation

/// A canteen meal paid with WeChat reaches `card/getRecordList` as two records with the same
/// voucher, day, time and amount: WeChat's money coming in (a flag other than 「1」, 「微信支付」 or
/// 「POS消费」 in its name, no top-up word) and the canteen's payment (flag 「1」). The balance
/// does not move, but the meal was spent once: the pair is one canteen expense, the payment
/// tagged `paidWithWeChat`.
///
/// The other half may still be on a page not read yet: until the day is read through, a WeChat
/// half without its partner is left out (neither shown nor counted). After that it is money in.
public enum WeChatPairs {
    /// `rows` with each pair made one expense, in the school's order. `isRead(day)` (`yyyyMMdd`)
    /// says every record of that day has come, so a half still alone has no partner.
    public static func merged(_ rows: [CardRecord], isRead: (String) -> Bool) -> [CardRecord] {
        struct Key: Hashable { var voucher, date, time: String; var fen: Int }
        func key(_ row: CardRecord) -> Key? {
            guard let voucher = row.voucher, !voucher.isEmpty else { return nil }
            return Key(voucher: voucher, date: CardHistory.trimmed(row.date), time: CardHistory.trimmed(row.time),
                       fen: abs(row.amount.fen))
        }
        var halves: [Key: [Int]] = [:], payments: [Key: [Int]] = [:]
        for (i, row) in rows.enumerated() {
            guard let k = key(row) else { continue }
            if row.isWeChatHalf {
                halves[k, default: []].append(i)
            } else if CardRecord.flag(row.direction) == "1", row.flow == .moneyOut {
                payments[k, default: []].append(i)
            }
        }
        // Exactly one of each: anything else is left as the school sent it.
        var dropped = Set<Int>(), tagged = Set<Int>()
        for (k, h) in halves where h.count == 1 {
            guard let p = payments[k], p.count == 1 else { continue }
            dropped.insert(h[0]); tagged.insert(p[0])
        }
        return rows.enumerated().compactMap { i, row in
            if dropped.contains(i) { return nil }
            if tagged.contains(i) { var row = row; row.paidWithWeChat = true; return row }
            // Without a voucher it can never be paired: nothing to wait for.
            if row.isWeChatHalf, key(row) != nil, !isRead(CardHistory.trimmed(row.date)) { return nil }
            return row
        }
    }
}

extension CardRecord {
    /// Looks like WeChat's half of a meal paid with WeChat: money in (a flag other than 「1」)
    /// named 「微信支付」 or 「POS消费」, without a top-up or refund word (「备付金充值(微信支付(手机))」
    /// is a top-up). Alone, it is money in.
    var isWeChatHalf: Bool {
        let flag = CardRecord.flag(direction)
        guard !flag.isEmpty, flag != "1" else { return false }
        let n = title.filter { !$0.isWhitespace }
        guard n.contains("微信支付") || n.contains("POS消费") else { return false }
        return !CardFlow.incomeWords.contains(where: n.contains)
    }
}

public extension CardActivity {
    /// The home read of one page: pairs made one expense (before the vouchers are dropped, as
    /// 最近 and the widget's snapshot keep none). On a page that did not hold every record, a
    /// WeChat half on the page's oldest day may have its partner on the next page and is left out.
    init(page: CardRecordPage, begin: String, end: String, pageSize: Int) {
        let complete = page.isComplete(pageSize: pageSize)
        let oldest = page.rows.map { CardHistory.trimmed($0.date) }.min()
        let rows = WeChatPairs.merged(page.rows) { day in complete || oldest.map { day > $0 } ?? false }
            .map { row in var row = row; row.voucher = nil; return row }
        self.init(records: rows, begin: begin, end: end, complete: complete)
    }
}
