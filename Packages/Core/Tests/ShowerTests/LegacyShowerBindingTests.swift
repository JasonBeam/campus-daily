import XCTest
@testable import Core

/// SecureStore wrapper that counts writes per key.
final class CountingSecureStore: SecureStore, @unchecked Sendable {
    let inner = InMemorySecureStore()
    private let lock = NSLock()
    private var counts: [StoreKey: Int] = [:]
    func read(_ key: StoreKey) throws -> Data? { try inner.read(key) }
    func write(_ data: Data, for key: StoreKey) throws {
        try inner.write(data, for: key)
        lock.withLock { counts[key, default: 0] += 1 }
    }
    func delete(_ key: StoreKey) throws { try inner.delete(key) }
    func create(_ data: Data, for key: StoreKey) throws -> Bool { try inner.create(data, for: key) }
    func replace(_ data: Data, for key: StoreKey) throws -> Bool { try inner.replace(data, for: key) }
    func writes(_ key: StoreKey) -> Int { lock.withLock { counts[key, default: 0] } }
}

/// Bindings saved by builds that could use the online access service.
final class LegacyShowerBindingTests: XCTestCase {
    /// The old shape: the direct fields plus an `access` grant (synthetic values).
    static let legacyJSON = Data("""
    {"studentId":"S1234567","schoolId":"20021","machineId":"11223344","roomId":"R1","roomLabel":"99栋 991",
     "machineName":"99-991","peripheralID":"P-SYNTH-1",
     "access":{"token":"SYNTH-ACCESS-TOKEN","campusOwner":"synthetic","expiresAt":1793300000000,
               "bleName":"SYNTH","typeID":1,"version":2}}
    """.utf8)

    static let direct = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1",
                                      roomLabel: "99栋 991", machineName: "99-991", peripheralID: "P-SYNTH-1")

    func testOldBindingWithAccessDecodesAsADirectBinding() throws {
        let store = CountingSecureStore()
        try store.inner.write(Self.legacyJSON, for: .showerBinding)
        let binding = try XCTUnwrap(try StoredShowerVault(store: store).binding())
        XCTAssertEqual(binding, Self.direct)
        // Nothing about the access service survives in the value the engine gets.
        let encoded = try JSONValue.parse(try JSONEncoder().encode(binding))
        guard case .object(let fields) = encoded else { return XCTFail() }
        XCTAssertEqual(Set(fields.keys), ["studentId", "schoolId", "machineId", "roomId", "roomLabel", "machineName", "peripheralID"])
    }

    func testReadingTheOldFormatSavesItOnceWithoutTheToken() throws {
        let store = CountingSecureStore()
        try store.inner.write(Self.legacyJSON, for: .showerBinding)
        let vault = StoredShowerVault(store: store)
        _ = try vault.binding()
        XCTAssertEqual(store.writes(.showerBinding), 1)
        let stored = try XCTUnwrap(try store.read(.showerBinding))
        XCTAssertFalse(StoredShowerVault.hasLegacyAccess(stored))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("SYNTH-ACCESS-TOKEN"))
        XCTAssertEqual(try vault.binding(), Self.direct)
        XCTAssertEqual(store.writes(.showerBinding), 1, "a current binding is never rewritten on read")
    }

    func testFailedResaveStillReturnsTheBindingAndRetriesNextRead() throws {
        let store = CountingSecureStore()
        try store.inner.write(Self.legacyJSON, for: .showerBinding)
        store.inner.failWrites(to: .showerBinding)
        let vault = StoredShowerVault(store: store)
        XCTAssertEqual(try vault.binding(), Self.direct)
        XCTAssertTrue(StoredShowerVault.hasLegacyAccess(try XCTUnwrap(try store.read(.showerBinding))))
        store.inner.failWrites(to: .showerBinding, false)
        XCTAssertEqual(try vault.binding(), Self.direct)
        XCTAssertFalse(StoredShowerVault.hasLegacyAccess(try XCTUnwrap(try store.read(.showerBinding))))
    }

    func testUnreadableBindingStillThrows() throws {
        let store = InMemorySecureStore()
        try store.write(Data("{".utf8), for: .showerBinding)
        XCTAssertThrowsError(try StoredShowerVault(store: store).binding()) { XCTAssertTrue($0 is StorageError) }
    }
}
