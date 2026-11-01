import Foundation

/// Onboarding: portal dorm address → area path (campus → building → floor → room) → controller.
/// Stops at the first level without exactly one match and hands the options to a manual picker;
/// never guesses a room or a controller.
public struct ShowerOnboarding: Sendable {
    public enum Level: Int, Sendable, Codable, CaseIterable { case campus, building, floor, room }

    public enum Result: Sendable, Equatable {
        /// The full path matched and the room has exactly one controller.
        case matched(path: [AreaNode], machine: ShowerMachine)
        /// The room has several controllers: the user picks (then the BLE identity check binds).
        case chooseMachine(path: [AreaNode], machines: [ShowerMachine])
        /// Zero or several names fit at `level`: manual picker over `options`, starting below `path`.
        case pick(level: Level, options: [AreaNode], path: [AreaNode])
        /// The room exists but has no controller (`5000` or an empty list): "这个房间没有水控".
        case noController(path: [AreaNode], message: String)
        /// The platform does not know an address node (`4034`): "学校没有登记这个地址".
        case addressUnknown(message: String)
    }

    public static let noControllerText = "这个房间没有水控"
    public static let addressUnknownText = "学校没有登记这个地址"

    let directory: ShowerDirectory
    public init(directory: ShowerDirectory) { self.directory = directory }

    /// `schoolId` is the platform school id (`getUserMsg.schoolid`), the root of the area tree.
    public func match(_ address: DormAddress, schoolId: String) async throws -> Result {
        var path: [AreaNode] = []
        var parent = schoolId
        do {
            for level in Level.allCases {
                let options = level == .room ? try await directory.rooms(floor: parent) : try await directory.areas(parent: parent)
                let hits = options.filter { Self.matches($0.name, level: level, address: address) }
                guard hits.count == 1, let hit = hits.first else {
                    return .pick(level: level, options: options, path: path)
                }
                path.append(hit)
                parent = hit.id
            }
        } catch ServiceError.rejected(.lxt6, "4034", let message) {
            return .addressUnknown(message: message.isEmpty ? Self.addressUnknownText : message)
        }
        return try await controllers(path: path, schoolId: schoolId)
    }

    /// Controllers of the last node of `path` (also used after a manual pick).
    public func controllers(path: [AreaNode], schoolId: String) async throws -> Result {
        guard let room = path.last else { return .pick(level: .campus, options: [], path: []) }
        let machines: [ShowerMachine]
        do {
            machines = try await directory.machines(room: room.id, schoolId: schoolId)
        } catch ServiceError.rejected(.lxt6, "5000", _) {
            // The server's "系统提示： 当前房间未绑定设备" is shown as our own sentence.
            return .noController(path: path, message: Self.noControllerText)
        } catch ServiceError.rejected(.lxt6, "4034", let message) {
            return .addressUnknown(message: message.isEmpty ? Self.addressUnknownText : message)
        }
        switch machines.count {
        case 0: return .noController(path: path, message: Self.noControllerText)
        case 1: return .matched(path: path, machine: machines[0])
        default: return .chooseMachine(path: path, machines: machines)
        }
    }

    public static func matches(_ name: String, level: Level, address: DormAddress) -> Bool {
        switch level {
        case .campus: return address.matchesCampus(name)
        case .building: return address.matchesBuilding(name)
        case .floor: return address.matchesFloor(name)
        case .room: return address.matchesRoom(name)
        }
    }

    /// Every node of a (service-provided) path fits the address at its level.
    public static func pathMatches(_ path: [AreaNode], address: DormAddress) -> Bool {
        path.count <= Level.allCases.count && path.enumerated().allSatisfy { i, node in
            matches(node.name, level: Level.allCases[i], address: address)
        }
    }

    /// The binding label, e.g. "99栋 991".
    public static func roomLabel(_ path: [AreaNode]) -> String {
        guard path.count == 4 else { return path.map(\.name).joined(separator: " ") }
        return path[1].name + " " + path[3].name
    }
}
