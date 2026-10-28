import Foundation

/// An explicit residence from the authenticated portal. No inference from a
/// student number, card balance, nearby radio or another account's settings.
public struct PortalDormAddress: Sendable, Equatable {
    public let campus: String
    public let building: String
    public let unit: String?
    public let floor: Int
    public let room: String
    public var shortRoom: String { building + "栋" + room }
    public static func parse(_ raw: String) -> Self? {
        let text = raw.filter { !$0.isWhitespace }
        guard text.count <= 128,
              let regex = try? NSRegularExpression(pattern:"^(.{1,32}校区)([A-Za-z]?[0-9]{1,3})(?:栋|幢)(?:([0-9]{1,3})号)?([0-9]{1,2})(?:层|楼)([0-9]{2,6}[A-Za-z]?)(?:房|室)$"),
              let match = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
        func part(_ i: Int) -> String { Range(match.range(at:i),in:text).map {String(text[$0])} ?? "" }
        guard let floor = Int(part(4)), floor > 0 else { return nil }
        return Self(campus:part(1),building:part(2),unit:part(3).isEmpty ? nil : part(3),floor:floor,room:part(5))
    }
    public func matches(_ label: String, level: Int) -> Bool {
        let value = label.filter { !$0.isWhitespace }
        switch level {
        case 0: return value == campus
        case 1: return [building+"栋",building+"幢",building+"号楼"].contains(value)
        case 2:
            let chinese = ["零","一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]
            let number = floor < chinese.count ? chinese[floor] : String(floor)
            return ["\(floor)楼","\(floor)层",number+"楼",number+"层"].contains(value)
        case 3: return [room,room+"房",room+"室"].contains(value)
        default: return false
        }
    }
    public func matchesUnit(_ label: String) -> Bool {
        guard let unit else {return false}
        return [unit+"号",unit+"单元"].contains(label.filter{!$0.isWhitespace})
    }
    public func powerBranchCandidates(_ labels: [String]) -> [String] {
        if labels.contains(where:{$0.range(of:"[0-9]+(?:栋|幢|号楼)$",options:.regularExpression) != nil}) {return labels.filter{matches($0,level:1)}}
        if labels.contains(where:{$0.range(of:"[0-9]+(?:号|单元)$",options:.regularExpression) != nil}) {return labels.filter{matchesUnit($0)}}
        if labels.contains(where:{$0.range(of:"[0-9一二三四五六七八九十]+(?:楼|层)$",options:.regularExpression) != nil}) {return labels.filter{matches($0,level:2)}}
        if labels.contains(where:{$0.range(of:"^[0-9]{2,6}(?:房|室)?$",options:.regularExpression) != nil}) {return labels.filter{matches($0,level:3)}}
        return labels
    }
    public func matchesMeterRoom(_ label: String) -> Bool {
        let normalized = label.filter { !$0.isWhitespace && $0 != "·" }
        return [shortRoom,shortRoom+"房",shortRoom+"室"].contains(normalized)
    }
}

public struct CampusPowerSuggestion: Sendable {
    public let building: String
    public let meter: CampusElectricity
}

@MainActor public enum CampusPowerResolver {
    /// Resolve the power platform's own IDs within the explicit portal address.
    /// Ambiguous names and partial results never become a binding.
    public static func suggest(address: PortalDormAddress, readBuildings: (String?) async throws -> [CampusPowerBuilding], readMeters: (String) async throws -> [CampusElectricity]) async throws -> CampusPowerSuggestion? {
        let campuses = try await readBuildings(nil).filter { address.matches($0.name,level:0) }
        guard campuses.count == 1 else { return nil }
        var queue = [(campuses[0].id,0)], visits = 0
        var matches: [CampusPowerSuggestion] = []
        while !queue.isEmpty && visits < 32 {
            try Task.checkCancellation()
            let (parent,depth) = queue.removeFirst(); visits += 1
            let children = try await readBuildings(parent)
            if children.isEmpty {
                for meter in try await readMeters(parent) where address.matchesMeterRoom(meter.room) {
                    matches.append(CampusPowerSuggestion(building:parent,meter:meter))
                    if matches.count > 1 { return nil }
                }
                continue
            }
            guard depth < 5 else { return nil }
            let names = Set(address.powerBranchCandidates(children.map(\.name)))
            let next = children.filter {names.contains($0.name)}
            guard next.count <= 12 else { return nil }
            queue += next.map { ($0.id,depth+1) }
        }
        guard queue.isEmpty, matches.count == 1 else { return nil }
        return matches.first
    }
}

public extension CampusProvider {
    func suggestPower(config: CampusConfig, address: PortalDormAddress) async throws -> CampusPowerSuggestion? {
        try await CampusPowerResolver.suggest(address:address,
            readBuildings:{try await self.powerBuildings(config:config,parent:$0)},
            readMeters:{try await self.powerMeters(config:config,building:$0)})
    }
}
