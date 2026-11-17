import Foundation

public enum LaundryStartAttempt: String, Codable, Sendable { case requested, accepted, confirmed, blocked }

public enum LaundryImmediatePolling {
    public static func needed(_ record: LaundryCheckoutRecord?, now: Date = Date()) -> Bool {
        guard let record, record.immediateStart == true, record.stage != .completed,
              record.startAttempt != .blocked, record.order?.running != true else { return false }
        return (0...600).contains(now.timeIntervalSince(record.createdAt))
    }
    public static func interval(_ record: LaundryCheckoutRecord?, activeSince: Date, now: Date = Date()) -> TimeInterval {
        guard needed(record,now:now) else { return 30 }
        return (0..<20).contains(now.timeIntervalSince(activeSince)) ? 1 : 3
    }
}

/// Official H5 order detail: the app environment uses the documented remote-control branch.
public struct LaundryStartDetails: Decodable, Sendable {
    public let order: LaundryOrder
    public let moduleType: Int?
    public let online: Bool?
    public let requiresSelfClean: Bool
    private enum Keys: String, CodingKey { case moduleType, online, selfCleanEnable, selfCleanPrice, cleanSelfEndTime, wp_order }
    public init(from decoder: Decoder) throws {
        order = try LaundryOrder(from:decoder)
        let c = try decoder.container(keyedBy:Keys.self)
        func integer(_ key: Keys) -> Int? {
            if let v = try? c.decode(Int.self,forKey:key) { return v }
            return (try? c.decode(String.self,forKey:key)).flatMap(Int.init)
        }
        func flag(_ key: Keys) -> Bool? {
            if let v = try? c.decode(Bool.self,forKey:key) { return v }
            return integer(key).map { $0 != 0 }
        }
        moduleType = integer(.moduleType); online = flag(.online)
        let completed = (try? c.decode(String.self,forKey:.cleanSelfEndTime)).map { !$0.isEmpty } ?? false
        let price = (try? c.decode(Decimal.self,forKey:.selfCleanPrice)) ??
            ((try? c.decode(String.self,forKey:.selfCleanPrice)).flatMap { Decimal(string:$0) } ?? 0)
        // Dispenser orders have an additional prepareWP flow. This candidate leaves those with U净.
        let hasDispenser = c.contains(.wp_order) && (try? c.decodeNil(forKey:.wp_order)) == false
        requiresSelfClean = hasDispenser || (!completed && flag(.selfCleanEnable) == true && price > 0)
    }
}

private struct LaundryStartAck: Decodable { let errorMessage: String?; init() { errorMessage = nil } }

extension LaundryProvider {
    public static func immediateOrderPath(id: String, control: Bool) throws -> String {
        guard validOrderId(id) else { throw LaundryError.response }
        // From official cf45 environment=app + b775 baseURL + startDevices API mapping.
        return "/api/v1/app/orders/\(id)/" + (control ? "control/start" : "detail?additional=price")
    }
    public func startDetails(config: LaundryConfig, id: String) async throws -> LaundryStartDetails {
        try config.validate()
        return try await request(Self.immediateOrderPath(id:id,control:false),config:config)
    }
    public func startWasher(config: LaundryConfig, id: String) async throws {
        try config.validate()
        let ack: LaundryStartAck = try await request(Self.immediateOrderPath(id:id,control:true),config:config,emptyValue:LaundryStartAck())
        guard ack.errorMessage?.isEmpty != false else { throw LaundryError.response }
    }
}
