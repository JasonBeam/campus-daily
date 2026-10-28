import Foundation

public struct CampusPowerBuilding: Identifiable, Sendable {
    public let id: String
    public let name: String
}
public struct CampusElectricity: Codable, Identifiable, Sendable {
    public let id: String
    public let room: String
    public let remainingKWh: Decimal
    public let balanceYuan: Decimal
    public let yesterdayKWh: Decimal?
    public let meterUpdatedAt: String
}
public enum CampusElectricityParser {
    public static func buildings(_ input: Any) throws -> [CampusPowerBuilding] {
        guard let rows = input as? [[String:Any]], rows.count <= 10000 else { throw CampusError.response }
        let values = try rows.map { row -> CampusPowerBuilding in
            guard let id = row["buildingID"] as? String, !id.isEmpty, id.count <= 128,
                  let name = row["buildingName"] as? String, !name.isEmpty, name.count <= 128 else { throw CampusError.response }
            return CampusPowerBuilding(id:id,name:name)
        }
        guard Set(values.map(\.id)).count == values.count else { throw CampusError.ambiguous }
        return values
    }
    public static func meters(_ input: Any) throws -> [CampusElectricity] {
        guard let rows = input as? [[String:Any]], rows.count <= 100 else { throw CampusError.response }
        let values = try rows.map { row -> CampusElectricity in
            guard let id = row["comAddress"] as? String, !id.isEmpty, id.count <= 128,
                  let room = row["piplineName"] as? String, !room.isEmpty, room.count <= 128 else { throw CampusError.response }
            let remaining = try CampusParser.amount(row["remaining"] as Any)
            let balance = try CampusParser.amount(row["leftMoney"] as Any)
            let yesterday = row["preUseDay"].flatMap { try? CampusParser.amount($0) }
            return CampusElectricity(id:id,room:room,remainingKWh:remaining,balanceYuan:balance,
                yesterdayKWh:yesterday,meterUpdatedAt:String((row["updateDateTime"] as? String ?? "").prefix(80)))
        }
        guard Set(values.map(\.id)).count == values.count else { throw CampusError.ambiguous }
        return values
    }
    public static func select(_ meters: [CampusElectricity], id: String) throws -> CampusElectricity {
        if !id.isEmpty {
            guard let value = meters.first(where:{ $0.id == id }) else { throw CampusError.response }
            return value
        }
        guard meters.count == 1, let value = meters.first else { throw CampusError.ambiguous }
        return value
    }
}
