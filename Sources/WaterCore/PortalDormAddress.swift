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
    public static func hasMoved(from old: String, to new: String) -> Bool {
        guard let before = parse(old), let after = parse(new) else {return false}
        return before != after
    }
    /// Mark an existing water binding for review before persisting a login
    /// whose ownership or known residence differs. Missing prior ownership is
    /// not evidence that the existing binding belongs to the new account.
    public static func needsWaterReview(hasBinding: Bool, previousOwner: String?, currentOwner: String, oldAddress: String, newAddress: String) -> Bool {
        guard hasBinding else { return false }
        guard let previousOwner, !previousOwner.isEmpty, previousOwner == currentOwner else { return true }
        return hasMoved(from:oldAddress,to:newAddress)
    }
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
    /// A display-label change must not discard a known meter for the same
    /// explicitly selected residence. Different campuses/rooms remain separate.
    public func keepsPowerBinding(selection: [String], savedRoom: String, meterRoom: String?) -> Bool {
        guard selection.count == 4, selection.enumerated().allSatisfy({matches($0.element,level:$0.offset)}) else {return false}
        if let meterRoom, matchesMeterRoom(meterRoom) {return true}
        if matchesMeterRoom(savedRoom) {return true}
        let old = savedRoom.components(separatedBy:" · ")
        return old.count == 4 && old.enumerated().allSatisfy({matches($0.element,level:$0.offset)})
    }
}

public struct CampusPowerSuggestion: Sendable {
    public let building: String
    public let meter: CampusElectricity
}

/// A complete, server-provided directory path. IDs are never shared with water.
public struct CampusPowerCandidate: Identifiable, Sendable {
    public let path: [CampusPowerBuilding]
    public var id: String { path.last!.id }
    public var label: String { path.dropFirst().map(\.name).joined(separator:" · ") }
}
public struct CampusPowerResolution: Sendable {
    public let suggestion: CampusPowerSuggestion?
    public let choices: [CampusPowerCandidate]
}

@MainActor public enum CampusPowerResolver {
    /// Complete directory discovery precedes meter reads. Duplicate apartment
    /// paths are a user choice, never a first-result or balance-based guess.
    public static func resolve(address: PortalDormAddress, readBuildings: (String?) async throws -> [CampusPowerBuilding], readMeters: (String) async throws -> [CampusElectricity]) async throws -> CampusPowerResolution {
        let none = CampusPowerResolution(suggestion:nil,choices:[])
        let campuses = try await readBuildings(nil).filter { address.matches($0.name,level:0) }
        guard campuses.count == 1 else { return none }
        var queue = [[campuses[0]]], visited = Set<String>(), leaves: [CampusPowerCandidate] = []
        while !queue.isEmpty {
            try Task.checkCancellation()
            let path = queue.removeFirst(), parent = path.last!.id
            guard visited.count < 64, visited.insert(parent).inserted else { return none }
            let children = try await readBuildings(parent)
            if children.isEmpty {
                // A generic apartment leaf is not an identified residence.
                if path.contains(where:{address.matches($0.name,level:1)}),
                   path.contains(where:{address.matches($0.name,level:2) || address.matches($0.name,level:3)}) {
                    leaves.append(CampusPowerCandidate(path:path))
                }
                continue
            }
            guard path.count < 7 else { return none }
            let names = Set(address.powerBranchCandidates(children.map(\.name)))
            let next = children.filter {names.contains($0.name)}
            guard next.count <= 24 else { return none }
            queue += next.map {path + [$0]}
        }
        guard leaves.count == 1, let only = leaves.first else {
            return CampusPowerResolution(suggestion:nil,choices:leaves)
        }
        return CampusPowerResolution(suggestion:try await select(only,address:address,readMeters:readMeters),choices:[])
    }
    public static func select(_ candidate: CampusPowerCandidate, address: PortalDormAddress, readMeters: (String) async throws -> [CampusElectricity]) async throws -> CampusPowerSuggestion? {
        let path = candidate.path
        guard path.first.map({address.matches($0.name,level:0)}) == true,
              path.contains(where:{address.matches($0.name,level:1)}) else {return nil}
        let exactRoomPath = path.contains(where:{address.matches($0.name,level:2)}) && path.contains(where:{address.matches($0.name,level:3)})
        let meters = try await readMeters(candidate.id).filter {
            address.matchesMeterRoom($0.room) || (exactRoomPath && address.matches($0.room,level:3))
        }
        guard meters.count == 1, let meter = meters.first else {return nil}
        return CampusPowerSuggestion(building:candidate.id,meter:meter)
    }
    public static func suggest(address: PortalDormAddress, readBuildings: (String?) async throws -> [CampusPowerBuilding], readMeters: (String) async throws -> [CampusElectricity]) async throws -> CampusPowerSuggestion? {
        try await resolve(address:address,readBuildings:readBuildings,readMeters:readMeters).suggestion
    }
}

public extension CampusProvider {
    func resolvePower(config: CampusConfig, address: PortalDormAddress) async throws -> CampusPowerResolution {
        try await CampusPowerResolver.resolve(address:address,
            readBuildings:{try await self.powerBuildings(config:config,parent:$0)},
            readMeters:{try await self.powerMeters(config:config,building:$0)})
    }
    func suggestPower(config: CampusConfig, address: PortalDormAddress) async throws -> CampusPowerSuggestion? {
        try await resolvePower(config:config,address:address).suggestion
    }
}

/// Pending reads must survive a same-room display-label save, but may never
/// replace a manual selection, changed account, campus, or portal residence.
public struct CampusPowerMatchScope: Sendable {
    private let config: CampusConfig
    public init(_ config: CampusConfig) {self.config = config}
    public func accepts(_ current: CampusConfig) -> Bool {
        guard config.syscustid == current.syscustid, config.custid == current.custid,
              config.areacode == current.areacode, config.accToken == current.accToken,
              config.portalDormAddress == current.portalDormAddress,
              config.buildingID == current.buildingID, config.meterID == current.meterID,
              let address = PortalDormAddress.parse(config.portalDormAddress) else {return false}
        return current.dormRoom == config.dormRoom || address.matchesMeterRoom(current.dormRoom)
    }
}
