import Foundation

public enum ElectricityResolution: Sendable, Equatable {
    /// Exactly one meter matched; the binding is saved.
    case matched(MeterBinding, Meter)
    /// Several rooms carry the dorm's number: the user picks one by its full location.
    case chooseAmong([MeterCandidate])
    /// A level of the directory did not match the dorm exactly once: the picker opens there.
    case stopped(MeterWalkStop)
    /// Several apartments (or campuses) hold the dorm's building and one of them could not be
    /// read (slow school, no connection): which one has the room is not known. Nothing bound.
    /// The stop is that level's, as a plain stop would be (its `path` for the page's path card).
    case unfinished(MeterWalkStop)
    /// No parsed portal dorm address.
    case noAddress
    /// A meter was bound meanwhile (picked by hand while the lookup ran): it stays, and is
    /// what the lookup answers with.
    case alreadyBound(MeterBinding)
}
