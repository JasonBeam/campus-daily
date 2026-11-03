import Foundation

/// Electricity: the dorm's meter, found by walking the school's power directory, chosen by
/// hand, and read.
extension SchoolSession {
    /// The automatic lookup: walks the directory the picker walks (校区 → 公寓 → 楼栋 → 楼层 →
    /// 房间), one small read per level, matching the dorm address. Every level matched once:
    /// the room's meter is bound (its node read, 1 row). A level matching none or several:
    /// stopped there (`.stopped`), the levels above kept, nothing bound. Several rooms of the
    /// dorm's number: the list to choose from. Each read is tried again after a timeout or no
    /// connection (`meterRetryDelays`).
    public func resolveElectricity() async throws -> ElectricityResolution {
        guard let session = try vault.ecyktSession() else { throw ServiceError.sessionExpired(.ecykt) }
        let started = personGeneration
        var profile = try vault.profile() ?? SchoolProfile()
        if profile.residence?.address == nil, let token = try vault.portalToken() {
            let residence = try await portal.myInfo(token)
            try ensureSignedIn(since: started)
            // Read again: a meter picked meanwhile is kept.
            profile = try vault.profile() ?? SchoolProfile()
            if profile.residence?.address == nil {
                profile.residence = residence
                try vault.saveProfile(profile)
            }
        }
        // Every answer, a list or a stop included, is the person's who started: someone else
        // signed in meanwhile gets none of it. A meter bound meanwhile (picked by hand) wins
        // over whatever the lookup found.
        guard let address = profile.residence?.address else {
            if case .bound(let b) = try settle(nil, since: started) { return .alreadyBound(b) }
            return .noAddress
        }
        let walked = try await walk(session, address: address, since: started)
        switch try settle(address, since: started) {
        case .bound(let b): return .alreadyBound(b)
        case .open(var current):
            switch walked {
            case .stopped(let stop), .noRoom(let stop): return .stopped(stop)
            case .unfinished(let at): return .unfinished(at)
            case .rooms(let list): return .chooseAmong(list)
            case .room(let found):
                guard let room = found.room else { return .chooseAmong([found]) }
                // Only the meter is written, onto the profile as it is now.
                let binding = MeterBinding(nodeID: room.id, comAddress: found.meter.comAddress, label: address.roomLabel,
                                           nodeIsRoom: true, location: found.location)
                current.meter = binding
                try vault.saveProfile(current)
                return .matched(binding, found.meter)
            }
        }
    }

    enum Walked {
        case room(MeterCandidate), rooms([MeterCandidate])
        /// Stopped before the rooms were read (a level not matched exactly once): the room may
        /// be there.
        case stopped(MeterWalkStop)
        /// Read down to the end: no room of the dorm's name with a meter. Shown as a stop.
        case noRoom(MeterWalkStop)
        /// A split at this level with one branch not read.
        case unfinished(MeterWalkStop)
        /// The rooms of the dorm's name this branch found with a meter.
        var found: [MeterCandidate] {
            switch self {
            case .unfinished, .noRoom: return []
            case .room(let c): return [c]
            case .rooms(let list): return list
            case .stopped(let stop): return stop.candidates
            }
        }
    }

    /// The walk itself. The portal names no apartment: when the campus lists apartments, the
    /// apartment is the one holding the dorm's building (each apartment's buildings read).
    /// Several apartments (or campuses) holding it: each is walked down to the rooms. Only one
    /// with the dorm's room: that one, as if it were the only one. Several: stopped at that
    /// level with their rooms as `candidates`. None: stopped there with nothing to choose.
    func walk(_ s: EcyktSession, address: DormAddress, since started: Int) async throws -> Walked {
        func children(_ parent: String?) async throws -> [PowerNode] {
            try await patiently(since: started) { try await self.ecykt.buildings(s, parent: parent) }
        }
        func ids(_ nodes: [PowerNode]) -> [String] { nodes.map(\.id) }

        /// Each branch walked down. Only a branch read to its rooms counts as without the room;
        /// one stopped before them (`halted`) may have it. The one branch with rooms of the
        /// dorm's name and none halted answers; one halted and none with rooms opens where it
        /// halted; several (or rooms and halted ones): `stop` with the rooms as `candidates` and
        /// the halted ones as `halted`. All without: `stop` as is.
        func split(_ walked: [(PowerNode, Walked)], _ stop: MeterWalkStop) -> Walked {
            var having: [(PowerNode, Walked)] = [], halted: [(PowerNode, MeterWalkStop)] = []
            for (branch, down) in walked {
                switch down {
                case .unfinished: return .unfinished(stop)
                case .noRoom: break
                case .stopped(let at) where at.candidates.isEmpty && at.halted.isEmpty: halted.append((branch, at))
                default: having.append((branch, down))
                }
            }
            if halted.isEmpty, having.count == 1 { return having[0].1 }
            if having.isEmpty, halted.count == 1 { return .stopped(halted[0].1) }
            if having.isEmpty, halted.isEmpty { return .noRoom(stop) }
            var stop = stop
            let chosen = Set(having.map(\.0.id) + halted.map(\.0.id))
            stop.suggested = walked.map(\.0.id).filter(chosen.contains)
            stop.candidates = having.flatMap(\.1.found)
            stop.halted = halted.map(\.1)
            return .stopped(stop)
        }

        /// One branch of a split walked down; nil when one of its reads failed for good (slow
        /// school, no connection): it cannot be counted as having no room. Signed out: thrown.
        func unlessUnread(_ down: () async throws -> Walked) async throws -> Walked? {
            do { return try await down() } catch let error as ServiceError where error == .timedOut || error == .offline {
                try ensureSignedIn(since: started)
                return nil
            }
        }

        /// From a building list (`buildings`, under `path`) down to the room's meter.
        func fromBuildings(_ buildings: [PowerNode], path: [PowerNode]) async throws -> Walked {
            var path = path
            let buildingHits = buildings.filter { address.matchesBuilding($0.name) }
            guard buildingHits.count == 1, let building = buildingHits.first else {
                return .stopped(MeterWalkStop(level: .building, path: path, options: buildings, suggested: ids(buildingHits)))
            }
            path.append(building)
            let floors = try await children(building.id)
            // Nothing under the building: read to the end.
            if floors.isEmpty { return .noRoom(MeterWalkStop(level: .floor, path: path, options: floors)) }
            var rooms = floors
            let floorHits = floors.filter { address.matchesFloor($0.name) }
            if floorHits.count == 1, let floor = floorHits.first {
                path.append(floor)
                rooms = try await children(floor.id)
            } else if !floors.contains(where: { address.matchesRoom($0.name) }) {
                // No floor level only when the building lists the rooms itself.
                return .stopped(MeterWalkStop(level: .floor, path: path, options: floors, suggested: ids(floorHits)))
            }
            let roomHits = rooms.filter { address.matchesRoom($0.name) }
            if roomHits.isEmpty { return .noRoom(MeterWalkStop(level: .room, path: path, options: rooms)) }
            guard roomHits.count <= Self.maxCandidateRooms else {
                return .stopped(MeterWalkStop(level: .room, path: path, options: rooms, suggested: ids(roomHits)))
            }
            var found: [MeterCandidate] = []
            for room in roomHits {
                let rows = try await patiently(since: started) { try await self.ecykt.meters(s, nodeID: room.id) }
                // The row of the dorm's name. A node's only row of another name is its meter only
                // when nothing is under it (a room): a bare-number floor of the room's number is not.
                let meter: Meter?
                switch MeterMatcher.match(rows, address: address) {
                case .one(let m): meter = m
                case .none:
                    if rows.count == 1 { meter = try await children(room.id).isEmpty ? rows.first : nil } else { meter = nil }
                case .many: meter = nil
                }
                if let meter { found.append(MeterCandidate(meter: meter, path: path + [room])) }
            }
            switch found.count {
            case 0: return .noRoom(MeterWalkStop(level: .room, path: path, options: rooms, suggested: ids(roomHits)))
            case 1: return .room(found[0])
            default: return .rooms(found)
            }
        }

        /// From a campus down: its buildings, or the apartments holding the dorm's building.
        func fromCampus(_ campus: PowerNode) async throws -> Walked {
            let path = [campus]
            let level1 = try await children(campus.id)
            if level1.contains(where: { address.matchesBuilding($0.name) }) { return try await fromBuildings(level1, path: path) }
            // The campus lists buildings itself and none is the dorm's: they are not apartments.
            if level1.contains(where: { MeterLevel.isBuilding($0.name) }) {
                return .noRoom(MeterWalkStop(level: .building, path: path, options: level1))
            }
            // Apartments: those holding a building of the dorm's name.
            guard level1.count <= Self.maxApartments else {
                return .stopped(MeterWalkStop(level: .apartment, path: path, options: level1))
            }
            var holding: [(PowerNode, [PowerNode])] = []
            for apartment in level1 {
                let kids = try await children(apartment.id)
                if kids.contains(where: { address.matchesBuilding($0.name) }) { holding.append((apartment, kids)) }
            }
            if holding.count == 1, let (apartment, kids) = holding.first {
                return try await fromBuildings(kids, path: path + [apartment])
            }
            let stop = MeterWalkStop(level: .apartment, path: path, options: level1, suggested: holding.map(\.0.id))
            guard holding.count > 1 else { return .noRoom(stop) }
            var walked: [(PowerNode, Walked)] = []
            for (apartment, kids) in holding {
                guard let down = try await unlessUnread({ try await fromBuildings(kids, path: path + [apartment]) }) else {
                    return .unfinished(stop)
                }
                walked.append((apartment, down))
            }
            return split(walked, stop)
        }

        let campuses = try await children(nil)
        let campusHits = campuses.filter { address.matchesCampus($0.name) }
        let stop = MeterWalkStop(level: .campus, path: [], options: campuses, suggested: ids(campusHits))
        switch campusHits.count {
        case 0: return .stopped(stop)
        case 1: return try await fromCampus(campusHits[0])
        default:
            var walked: [(PowerNode, Walked)] = []
            for campus in campusHits {
                guard let down = try await unlessUnread({ try await fromCampus(campus) }) else { return .unfinished(stop) }
                walked.append((campus, down))
            }
            return split(walked, stop)
        }
    }

    /// One read of the lookup, tried again after each of `meterRetryDelays` on a timeout or no
    /// connection. Signed out or someone else signed in since the lookup started: no read goes
    /// out with the old card session (`matchElectricity` runs the next person's own). Signed out
    /// while waiting to try again: the failure stands.
    private func patiently<T: Sendable>(since started: Int, _ read: () async throws -> T) async throws -> T {
        let signedOut = signOutGeneration
        var retries = 0
        while true {
            try ensureSignedIn(since: started)
            try Task.checkCancellation()
            do {
                return try await read()
            } catch let error as ServiceError where (error == .timedOut || error == .offline) && retries < Self.meterRetryDelays.count {
                try ensureSignedIn(since: started)
                guard signedOut == signOutGeneration else { throw error }
                await meterRetryWait(Self.meterRetryDelays[retries])
                retries += 1
                try Task.checkCancellation()
                guard signedOut == signOutGeneration, (try? vault.ecyktSession()) ?? nil != nil else { throw error }
                try ensureSignedIn(since: started)
            }
        }
    }

    private enum Settled { case bound(MeterBinding), open(SchoolProfile) }

    /// The dorm changed while the lookup ran (the same person signed in again and the school
    /// shows another one): what it found was for the old dorm. `matchElectricity` looks again.
    struct DormChangedDuringLookup: Error {}

    /// The lookup's reads for `address` are done: the profile as it is now, unless a meter was
    /// bound meanwhile. Someone else signed in meanwhile: thrown as an expired session; the dorm
    /// changed meanwhile: `DormChangedDuringLookup`.
    private func settle(_ address: DormAddress?, since started: Int) throws -> Settled {
        try ensureSignedIn(since: started)
        let current = try vault.profile() ?? SchoolProfile()
        if let bound = current.meter { return .bound(bound) }
        guard current.residence?.address == address else { throw DormChangedDuringLookup() }
        return .open(current)
    }

    /// `resolveElectricity()` for whoever is signed in when it answers, with the person stamp
    /// the answer belongs to (a same-name choice carries it into `chooseMatchedMeter`). Dropped
    /// because someone else signed in meanwhile, it runs again for them, a few times at most;
    /// signed out meanwhile (even where the sign-out failed), the drop is thrown.
    /// Each read's timeouts are tried again inside (`meterRetryDelays`); any other failure is
    /// thrown at once. The dorm changed while it ran: looked up again for the new one, a few
    /// times at most (then the picker from the campuses).
    public func matchElectricity() async throws -> (stamp: Int, ElectricityResolution) {
        var attempts = 0, dormChanges = 0
        while true {
            let stamp = personGeneration, signedOut = signOutGeneration
            do {
                return (stamp, try await resolveElectricity())
            } catch is DormChangedDuringLookup {
                dormChanges += 1
                guard dormChanges < 3 else { return (stamp, .stopped(MeterWalkStop(level: .campus, path: [], options: []))) }
            } catch {
                attempts += 1
                // A sign-out in between ends it, even one that could not delete the card session.
                guard stamp != personGeneration, signedOut == signOutGeneration, attempts < 3,
                      (try? vault.ecyktSession()) ?? nil != nil else { throw error }
            }
        }
    }

    /// The profile without `seen`, a campus-node meter, if it is still the one stored; nil when
    /// there is nothing to drop (another meter, or none, is stored now).
    public static func withoutCampusWideMeter(_ profile: SchoolProfile?, seen: MeterBinding) -> SchoolProfile? {
        guard !seen.nodeIsRoom, var profile, profile.meter == seen else { return nil }
        profile.meter = nil
        return profile
    }

    /// The profile with `seen` moved to the meter that replaced it in the same room
    /// (`comAddress`), if `seen` is still the one stored; nil when there is nothing to move
    /// (another meter, or none, is stored now).
    public static func withMeterMoved(_ profile: SchoolProfile?, seen: MeterBinding, to comAddress: String) -> SchoolProfile? {
        guard var profile, profile.meter == seen, seen.comAddress != comAddress else { return nil }
        profile.meter?.comAddress = comAddress
        return profile
    }

    /// The bound room's meter was replaced (`MeterMatcher.pick` read the new one): the binding
    /// follows it, in one locked step with the lease check, only while the stored binding is
    /// still the one this read used. Not written: the next refresh reads and tries again.
    func followReplacedMeter(_ seen: MeterBinding, to comAddress: String, owning: LeaseOwnership) {
        let vault = vault
        _ = try? owning.write {
            guard let next = Self.withMeterMoved(try vault.profile(), seen: seen, to: comAddress) else { return }
            try vault.saveProfile(next)
        }
    }

    /// Launch: a meter bound to the campus node (older builds) is dropped. True when one was.
    /// The dorm stays, so the launch lookup walks to the room's own meter. Compare-and-write in
    /// this actor: only the campus-node meter just read is removed, with no wait in between.
    public func dropCampusWideMeter() throws -> Bool {
        guard let seen = try vault.profile()?.meter, !seen.nodeIsRoom else { return false }
        guard let next = Self.withoutCampusWideMeter(try vault.profile(), seen: seen) else { return false }
        try vault.saveProfile(next)
        return true
    }

    /// Manual choice from the picker (`buildings(parent:)` walk in the UI, then a meter row).
    /// `path` = the directory names walked down to `nodeID`, kept as the full location.
    /// `stamp` = `personStamp()` when the picker opened: a pick made after someone else signed
    /// in is refused.
    public func chooseMeter(nodeID: String, meter: Meter, path: [String] = [], since stamp: Int) throws {
        try ensureSignedIn(since: stamp)
        var profile = try vault.profile() ?? SchoolProfile()
        profile.meter = MeterBinding(nodeID: nodeID, comAddress: meter.comAddress, label: meter.name, nodeIsRoom: true,
                                     location: path.isEmpty ? nil : PowerLocation.label(path))
        try vault.saveProfile(profile)
    }

    /// Choice among several same-name rooms (`.chooseAmong`): saved against its room node
    /// (1 row). A choice without its room is refused: no meter is bound to the campus.
    /// `stamp` = `personStamp()` taken before the match that offered the list.
    public func chooseMatchedMeter(_ candidate: MeterCandidate, since stamp: Int) async throws {
        try ensureSignedIn(since: stamp)
        guard let room = candidate.room else { throw ServiceError.malformed(.ecykt, "room") }
        var profile = try vault.profile() ?? SchoolProfile()
        guard let address = profile.residence?.address else { throw ServiceError.malformed(.portal, "data.gydz") }
        profile.meter = MeterBinding(nodeID: room.id, comAddress: candidate.meter.comAddress, label: address.roomLabel, nodeIsRoom: true,
                                     location: candidate.location)
        try vault.saveProfile(profile)
    }

    /// Manual picker: one level of the electricity directory (`nil` = campuses).
    public func directory(parent: String?) async throws -> [PowerNode] {
        guard let session = try vault.ecyktSession() else { throw ServiceError.sessionExpired(.ecykt) }
        return try await ecykt.buildings(session, parent: parent)
    }

    /// Manual picker: the meters at a directory node.
    public func meterRows(nodeID: String) async throws -> [Meter] {
        guard let session = try vault.ecyktSession() else { throw ServiceError.sessionExpired(.ecykt) }
        return try await ecykt.meters(session, nodeID: nodeID)
    }

    nonisolated func readMeter(_ session: EcyktSession, binding: MeterBinding?) async -> Result<Meter?, ServiceError>? {
        guard let binding else { return nil }
        // Bound to the campus node by an older build: no meter until the app drops it and finds the room.
        guard binding.nodeIsRoom else { return nil }
        return await capture {
            let rows = try await self.ecykt.meters(session, nodeID: binding.nodeID)
            return MeterMatcher.pick(rows, binding: binding)
        }
    }
}
