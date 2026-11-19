import Core

/// A fake school read that never writes a credential back, so it has no use for the lease
/// check or for early numbers: only the plain read to implement.
public protocol PlainSchoolReader: SchoolReader {
    func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool) async -> SchoolReading
}

public extension PlainSchoolReader {
    func refresh(inBackground: Bool, mayMint: @Sendable () async -> Bool, owning: LeaseOwnership,
                 numbers: @Sendable (SchoolReading) async -> Void) async -> SchoolReading {
        await refresh(inBackground: inBackground, mayMint: mayMint)
    }
}
