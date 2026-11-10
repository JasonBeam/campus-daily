import Foundation

/// A level of the electricity directory, as the picker walks it.
public enum MeterLevel: String, Sendable, Equatable, Codable, CaseIterable {
    case campus, apartment, building, floor, room
}

/// Where the automatic meter lookup stopped: the levels above matched the dorm (`path`), this
/// one did not match exactly once. The meter page opens here with `options` (this level's rows
/// as read); `suggested` are the rows that matched (several), or the dorm's own room when it
/// reports no meter; empty when nothing matched.
///
/// `candidates`: several rows of this level (apartments, or campuses) were walked down and more
/// than one holds a room of the dorm's name with a meter. Each is a room to bind as it is
/// (`SchoolSession.chooseMatchedMeter`); empty when there is nothing to choose from but the list.
/// `halted`: rows of this level whose walk stopped before reading the rooms (a level not matched
/// exactly once), each where it stopped; the room may be there, so none was bound.
public struct MeterWalkStop: Sendable, Equatable {
    public var level: MeterLevel
    public var path: [PowerNode]
    public var options: [PowerNode]
    public var suggested: [String]
    public var candidates: [MeterCandidate]
    public var halted: [MeterWalkStop]

    public init(level: MeterLevel, path: [PowerNode], options: [PowerNode], suggested: [String] = [],
                candidates: [MeterCandidate] = [], halted: [MeterWalkStop] = []) {
        self.level = level; self.path = path; self.options = options; self.suggested = suggested
        self.candidates = candidates; self.halted = halted
    }

    /// The row of this level a candidate lies under (「半山公寓」, or a campus).
    public func branch(of candidate: MeterCandidate) -> PowerNode? {
        candidate.path.indices.contains(path.count) ? candidate.path[path.count] : nil
    }

    /// The row of this level a halted branch lies under.
    public func branch(of halted: MeterWalkStop) -> PowerNode? {
        halted.path.indices.contains(path.count) ? halted.path[path.count] : nil
    }

    /// The name of `branch(of:)`, what the choice is titled with.
    public func branchName(_ candidate: MeterCandidate) -> String {
        branch(of: candidate)?.name ?? candidate.location
    }
}
