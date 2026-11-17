import Foundation
import CryptoKit

/// Local summaries only. Never derive a debit from balance changes or an expected price.
public struct LocalOrderRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let owner: String
    public let kind: String
    public let title: String
    public let startedAt: Date
    public let status: String
    public let amount: Decimal?
    public let amountLabel: String
    public static func digest(_ text: String) -> String {
        SHA256.hash(data:Data(text.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    public init(id:String,owner:String,kind:String,title:String,startedAt:Date,status:String,amount:Decimal?,amountLabel:String) {
        self.id=id;self.owner=owner;self.kind=kind;self.title=title;self.startedAt=startedAt
        self.status=status;self.amount=amount;self.amountLabel=amountLabel
    }
    public static func water(_ session:WaterSession) -> Self? {
        guard let owner=session.historyOwner, !owner.isEmpty else { return nil }
        let settled=session.stage == .settled
        return Self(id:digest("water|\(owner)|\(session.machineID)|\(session.startedAt.timeIntervalSinceReferenceDate)"),owner:owner,
            kind:"water",title:"热水洗澡",startedAt:session.startedAt,status:session.stage.label,
            amount:settled ? session.receipt?.amountYuan : nil,amountLabel:settled ? "结算金额" : "尚未确认扣费")
    }
    public static func laundry(_ record:LaundryCheckoutRecord) -> Self? {
        guard let owner=record.credentialIdentity, !owner.isEmpty else { return nil }
        // Local creation time stays stable before and after the server issues an order ID.
        let amount=record.order?.payPrice
        return Self(id:digest("laundry|\(owner)|\(record.deviceId)|\(record.createdAt.timeIntervalSinceReferenceDate)"),owner:owner,
            kind:"laundry",title:"洗衣 · " + record.programName,startedAt:record.createdAt,
            status:record.order?.label ?? "下单结果待核对",amount:amount,
            amountLabel:record.order?.paid == true ? "服务器订单金额（退款请到U净核对）" : "订单金额（未确认付款）")
    }
    public static func recent(_ records:[Self],owners:[String:String],now:Date=Date()) -> [Self] {
        var byID:[String:Self]=[:]
        for record in records where owners[record.kind] == record.owner && record.startedAt <= now && record.startedAt >= now.addingTimeInterval(-7*86400) {
            byID[record.id]=record
        }
        return byID.values.sorted { $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt > $1.startedAt }
    }
}
extension WaterConfig {
    public var historyOwner:String { LocalOrderRecord.digest(schoolID + "\0" + studentID) }
}
