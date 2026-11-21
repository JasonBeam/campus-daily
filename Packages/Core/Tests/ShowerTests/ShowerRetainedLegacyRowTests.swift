//
//  ShowerRetainedLegacyRowTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/18.
//

import XCTest
@testable import Core
import CoreTestSupport

/// `water.retained` holding rows an older or newer build wrote: an open shower that names no
/// controller, a phase this build doesn't know, something that is not a record at all. Such a
/// row never stops a new record from being kept. It stays byte for byte, is shown to nobody and
/// is never given an owner; a new record is appended after the old bytes, never re-encoded with
/// them. The live record (`water.session`) is read as strictly as before. Fakes only.
final class ShowerRetainedLegacyRowTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let legacyOpenRow = #"{"phase":"running","machineID":"11223344","stateReviewRequired":true}"#

    func binding(_ student: String) -> ShowerBinding {
        ShowerBinding(studentId: student, schoolId: "1", machineId: "11223344", roomId: "R-1", roomLabel: "3栋108")
    }

    /// A shower over and waiting for its check, as a next use keeps it.
    func waiting(_ minute: Double = 0) -> ShowerState {
        ShowerState(phase: .running, machineID: "11223344", peripheralID: "P", startedAt: t0.addingTimeInterval(minute * 60),
                    authorizationID: "A1", stateReviewRequired: true)
    }

    func vault(retained raw: String?, student: String? = "S-1") throws -> (StoredShowerVault, InMemorySecureStore) {
        let store = InMemorySecureStore()
        let vault = StoredShowerVault(store: store)
        if let student { try vault.saveBinding(binding(student)) }
        if let raw { try store.write(Data(raw.utf8), for: .showerRetained) }
        return (vault, store)
    }

    func stored(_ store: InMemorySecureStore) throws -> String {
        String(decoding: try XCTUnwrap(store.read(.showerRetained)), as: UTF8.self)
    }

    func elements(_ store: InMemorySecureStore) throws -> [JSONValue] {
        try XCTUnwrap(JSONValue.parse(XCTUnwrap(store.read(.showerRetained))).array)
    }

    func testALegacyOpenRowWithoutAControllerDoesNotBlockANewKeep() throws {
        let raw = "[\(legacyOpenRow)]"
        let (vault, store) = try vault(retained: raw)
        XCTAssertNoThrow(try vault.retainShower(waiting()))
        XCTAssertEqual(try vault.retainedShowersForBinding(), [waiting()])
        XCTAssertEqual(ShowerRetainedSummary.read(vault)?.count, 1)
        XCTAssertTrue(try stored(store).hasPrefix(String(raw.dropLast())), "the old bytes stay where they were")
    }

    func testOldRowsStayByteForByteOverSeveralKeeps() throws {
        let old = #"[ {"someLaterField":1.50, "phase":"running","machineID":"11223344"} ,{"phase":"idle","n":1e2}]"#
        let (vault, store) = try vault(retained: old)
        try vault.retainShower(waiting(1))
        try vault.retainShower(waiting(2))
        XCTAssertTrue(try stored(store).hasPrefix(String(old.dropLast())))
        XCTAssertEqual(try elements(store).count, 4)
        XCTAssertEqual(try vault.retainedShowersForBinding(), [waiting(1), waiting(2)])
    }

    func testAnUnknownPhaseRowIsKeptButNeverShownEvenWithKeptFor() throws {
        let row = #"{"phase":"someLaterPhase","keptFor":"S-1"}"#
        let (vault, store) = try vault(retained: "[\(row)]")
        XCTAssertEqual(try vault.retainedShowersForBinding(), [])
        XCTAssertEqual(try vault.retainedShowers(), [])
        XCTAssertNil(ShowerRetainedSummary.read(vault))
        XCTAssertNoThrow(try vault.retainShower(waiting()))
        XCTAssertEqual(try vault.retainedShowersForBinding(), [waiting()])
        XCTAssertTrue(try stored(store).hasPrefix("[\(row),"))
    }

    func testRowsThatAreNotRecordsAreKeptAndHidden() throws {
        let raw = #"[1,"x",null,[],{"machineID":"11223344","keptFor":"S-1"}]"#
        let (vault, store) = try vault(retained: raw)
        XCTAssertEqual(try vault.retainedShowers(), [])
        try vault.retainShower(waiting())
        XCTAssertTrue(try stored(store).hasPrefix(String(raw.dropLast()) + ","))
        XCTAssertEqual(try elements(store).count, 6)
        XCTAssertEqual(try vault.retainedShowersForBinding(), [waiting()])
    }

    func testALegacyRowIsNeverClaimed() throws {
        let raw = "[\(legacyOpenRow)]"
        let (vault, store) = try vault(retained: raw)
        try vault.retainShower(waiting())
        let elements = try elements(store)
        XCTAssertNil(elements[0]["keptFor"], "the old row gets no owner")
        XCTAssertEqual(elements[1]["keptFor"], .string("S-1"))
        XCTAssertEqual(try vault.retainedShowersForBinding(), [waiting()])

        try vault.saveBinding(binding("S-2"))
        XCTAssertEqual(try vault.retainedShowersForBinding(), [])
        XCTAssertNil(ShowerRetainedSummary.read(vault))
    }

    /// The record's own student (`studentId`, saved at its start) never stands in for `keptFor`.
    func testARecordsOwnStudentIsNotItsKeeper() throws {
        let row = #"{"phase":"running","machineID":"11223344","peripheralID":"P","stateReviewRequired":true,"studentId":"S-1"}"#
        let (vault, _) = try vault(retained: "[\(row)]")
        XCTAssertEqual(try vault.retainedShowers().count, 1)
        XCTAssertEqual(try vault.retainedShowersForBinding(), [])
        XCTAssertNil(ShowerRetainedSummary.read(vault))
    }

    func testAKeptOpenRowWithoutAControllerIsShownReadOnlyToItsStudent() throws {
        let row = #"{"phase":"running","machineID":"11223344","startedAt":\#(t0.timeIntervalSinceReferenceDate),"keptFor":"S-1"}"#
        let (vault, _) = try vault(retained: "[\(row)]")
        let shown = try vault.retainedShowersForBinding()
        XCTAssertEqual(shown.count, 1)
        XCTAssertNil(shown.first?.peripheralID)
        let summary = try XCTUnwrap(ShowerRetainedSummary.read(vault))
        XCTAssertEqual(summary.entries, [.init(started: t0, machine: "11223344", reason: .stopped)])
        XCTAssertEqual(Mirror(reflecting: summary.entries[0]).children.count, 3, "when, where and why only")

        try vault.saveBinding(binding("S-2"))
        XCTAssertNil(ShowerRetainedSummary.read(vault))
    }

    func testTheLiveRecordStillRefusesAnOpenShowerWithoutAController() throws {
        let store = InMemorySecureStore()
        try store.write(Data(legacyOpenRow.utf8), for: .showerSession)
        XCTAssertThrowsError(try StoredShowerVault(store: store).showerState()) {
            XCTAssertEqual($0 as? ShowerEngineError, .unreadableRecord)
        }
        XCTAssertThrowsError(try ShowerEngine(transport: FakeShowerTransport(), gateway: FakeGateway(), vault: StoredShowerVault(store: store),
                                              configuration: .init(bleName: "fixture-ble"))) {
            XCTAssertEqual($0 as? ShowerEngineError, .unreadableRecord)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ShowerState.self, from: Data(legacyOpenRow.utf8)))
    }

    func testKeptRowsKeepTheMaybeSentDefaults() throws {
        let rows = #"[{"phase":"running","machineID":"11223344","keptFor":"S-1"},{"phase":"closing","machineID":"11223344","keptFor":"S-1"}]"#
        let (vault, _) = try vault(retained: rows)
        let shown = try vault.retainedShowersForBinding()
        XCTAssertEqual(shown.count, 2)
        for s in shown {
            XCTAssertTrue(s.authorizeSent, "may have left")
            XCTAssertTrue(s.closeSent, "may have left")
        }
    }

    func testAKeepOverALegacyRowIsStillOnce() throws {
        let (vault, store) = try vault(retained: "[\(legacyOpenRow)]")
        try vault.retainShower(waiting())
        try vault.retainShower(waiting())
        XCTAssertEqual(try elements(store).count, 2)
        XCTAssertEqual(try vault.retainedShowersForBinding(), [waiting()])
    }

    func testAListThatIsNotAnArrayStillRefusesAKeep() throws {
        for raw in ["not json", #"{"phase":"idle"}"#, "[1,", "null"] {
            let (vault, store) = try vault(retained: raw)
            XCTAssertThrowsError(try vault.retainShower(waiting()), raw) {
                XCTAssertEqual($0 as? ShowerEngineError, .unreadableRecord, raw)
            }
            XCTAssertEqual(try stored(store), raw, "\(raw): nothing written over it")
        }
    }

    func testAKeepThatReadsBackWrongThrows() throws {
        let old = #"[{"phase":"idle","someLaterField":1}]"#
        // One byte in the old part (the 1), one in the new row's keeper.
        let changes: [(String, @Sendable (Data) -> Data)] = [
            ("old", { var d = $0; let i = d.firstIndex(of: UInt8(ascii: "1"))!; d[i] = UInt8(ascii: "2"); return d }),
            ("new", { var d = $0; let i = d.lastIndex(of: UInt8(ascii: "1"))!; d[i] = UInt8(ascii: "9"); return d }),
        ]
        for (label, corrupt) in changes {
            let store = TamperingStore(corrupt: corrupt)
            let vault = StoredShowerVault(store: store)
            try vault.saveBinding(binding("S-1"))
            try store.inner.write(Data(old.utf8), for: .showerRetained)
            XCTAssertThrowsError(try vault.retainShower(waiting()), label) {
                XCTAssertEqual($0 as? ShowerEngineError, .storage, label)
            }
        }
    }

    func testKeepingIntoAnEmptyArrayWithWhitespace() throws {
        for raw in ["[]", "[ ]", "[\n]", " [] ", "\t[ \r\n ]\n"] {
            let (vault, store) = try vault(retained: raw)
            XCTAssertNoThrow(try vault.retainShower(waiting()), raw)
            let text = try stored(store)
            let close = try XCTUnwrap(raw.lastIndex(of: "]"))
            XCTAssertTrue(text.hasPrefix(String(raw[..<close]) + "{"), "\(raw): the old bytes, then the new row, no comma")
            XCTAssertTrue(text.hasSuffix("}]"), raw)
            XCTAssertEqual(try elements(store).count, 1, raw)
            XCTAssertEqual(try vault.retainedShowersForBinding(), [waiting()], raw)
        }
    }

    func testKeepingAfterAListWithTrailingWhitespace() throws {
        let element = #"{"phase":"idle","machineID":"11223344"}"#
        let raw = "[\(element)]\n  "
        let (vault, store) = try vault(retained: raw)
        try vault.retainShower(waiting())
        let text = try stored(store)
        XCTAssertTrue(text.hasPrefix("[\(element),{"), "exactly one comma before the new row")
        XCTAssertTrue(text.hasSuffix("}]"), "the trailing whitespace is dropped")
        XCTAssertEqual(try elements(store).count, 2)
    }

    func testARepeatedKeepChangesNoBytes() throws {
        let (vault, store) = try vault(retained: "[\(legacyOpenRow), 7]")
        try vault.retainShower(waiting())
        let before = try XCTUnwrap(store.read(.showerRetained))
        let counting = TamperingStore(corrupt: { $0 })
        try counting.inner.write(before, for: .showerRetained)
        let again = StoredShowerVault(store: counting)
        try again.saveBinding(binding("S-1"))
        counting.writes = 0
        XCTAssertNoThrow(try again.retainShower(waiting()))
        XCTAssertEqual(counting.writes, 0, "nothing written")
        XCTAssertEqual(try counting.read(.showerRetained), before)
        XCTAssertNoThrow(try vault.retainShower(waiting()))
        XCTAssertEqual(try store.read(.showerRetained), before)
    }

    func testTheLastRowNamesTheCurrentStudent() throws {
        let (vault, store) = try vault(retained: "[\(legacyOpenRow)]")
        try vault.retainShower(waiting())
        let rows = try elements(store)
        XCTAssertEqual(rows.last?["keptFor"], .string("S-1"))
        XCTAssertTrue(try stored(store).hasPrefix("[\(legacyOpenRow),"), "the old row has no keptFor")
    }

    func testAFirstKeepWritesAOneRowList() throws {
        let (vault, store) = try vault(retained: nil)
        try vault.retainShower(waiting())
        XCTAssertEqual(try elements(store).count, 1)
        XCTAssertEqual(try vault.retainedShowersForBinding(), [waiting()])
        XCTAssertTrue(try stored(store).hasPrefix("[{"))
    }
}

/// An in-memory store that changes what is written to `water.retained` (as a faulty write
/// would) and counts those writes.
final class TamperingStore: SecureStore, @unchecked Sendable {
    let inner = InMemorySecureStore()
    private let lock = NSLock()
    private let corrupt: @Sendable (Data) -> Data
    private var _writes = 0
    var writes: Int { get { lock.withLock { _writes } } set { lock.withLock { _writes = newValue } } }

    init(corrupt: @escaping @Sendable (Data) -> Data) { self.corrupt = corrupt }

    func read(_ key: StoreKey) throws -> Data? { try inner.read(key) }
    func write(_ data: Data, for key: StoreKey) throws {
        guard key == .showerRetained else { return try inner.write(data, for: key) }
        writes += 1
        try inner.write(corrupt(data), for: key)
    }
    func delete(_ key: StoreKey) throws { try inner.delete(key) }
}
