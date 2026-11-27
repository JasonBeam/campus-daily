//
//  CardHistoryDiskCacheTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/27.
//

import XCTest
@testable import Core

/// Track 2 verification for `CardHistory+Cache`, `CardHistoryDiskCoordinator`, `CardRecordsLoader`
/// disk integration, and cross-day `SpendStats.make` behavior. Uses synthetic records and synthetic
/// identities only.
final class CardHistoryDiskCacheTests: XCTestCase {
    private let cal = SchoolCalendar.shanghai
    /// Tuesday 2026-11-24 12:00 in Shanghai.
    private var noon: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))! }

    private func id(back days: Int, from base: Date? = nil) -> String {
        SchoolCalendar.dayString(cal.date(byAdding: .day, value: -days, to: base ?? noon)!, calendar: cal)
    }

    private func makeRecord(_ date: String, yuan: String = "12.50", time: String = "120000",
                            title: String = "POS消费示例食堂", voucher: String = "99000000000000000001") -> CardRecord {
        CardRecord(date: date, time: time, title: title, amount: Money(yuanString: yuan)!,
                   balanceAfter: Money(yuanString: "80.00"), direction: "1", voucher: voucher)
    }

    private func makeTempRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xrc-card-history-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Builds a `CardHistory` with `ranges` finished 14-day ranges ending on `base`.
    private func makeHistory(ranges: Int = 3, base: Date? = nil, titlePrefix: String = "POS消费示例窗口",
                             reachedEnd: Bool = false) -> CardHistory {
        let anchor = base ?? noon
        var history = CardHistory(now: anchor, calendar: cal)
        var voucherSeq = 1
        for r in 0..<ranges {
            let query = history.nextQuery!
            var rows: [CardRecord] = []
            for offset in 0..<CardHistory.rangeDays {
                let dayBack = r * CardHistory.rangeDays + offset
                let dateID = id(back: dayBack, from: anchor)
                voucherSeq += 1
                rows.append(makeRecord(dateID, yuan: "10.00", time: "121500",
                                       title: "\(titlePrefix)-\(dayBack)",
                                       voucher: String(format: "99%018d", voucherSeq)))
            }
            history.receive(CardRecordPage(total: rows.count, rows: rows), for: query)
        }
        if reachedEnd { history.reachedEnd = true }
        return history
    }

    private func seedCommittedSession(store: InMemorySecureStore,
                                      epochID: String,
                                      phase: SessionEpoch.Phase = .active,
                                      unionID: String = "SYNTH_UNION_A",
                                      account: String? = "2026000001",
                                      cardIsFallback: Bool = false) throws {
        try SessionEpochStore(store: store).write(SessionEpoch(id: epochID, phase: phase))
        let vault = StoredSchoolVault(store: store)
        var ecykt = EcyktSession(
            token: "synth-token-\(epochID)",
            syscustid: "TESTsyscustid0001",
            cardUnionID: unionID,
            obtainedAt: noon
        )
        ecykt.cardIsFallback = cardIsFallback
        try vault.saveEcyktSession(ecykt)
        if let account {
            try vault.saveAccount(SchoolAccount(account: account))
        } else {
            try store.delete(.schoolPortal)
        }
    }

    /// Injectable file system wrapper around `LocalCardHistoryFileSystem` to simulate lock-screen
    /// `EPERM`/`EACCES` reads and directory deletion failures deterministically.
    private final class FaultyFileSystem: CardHistoryFileSystem, @unchecked Sendable {
        private let inner = LocalCardHistoryFileSystem()
        private let lock = NSLock()
        var failReadsWithPermission = false
        var failRemoves = false
        var readCallCount = 0

        func fileExists(at url: URL) -> Bool { inner.fileExists(at: url) }
        func fileSize(at url: URL) throws -> Int64 { try inner.fileSize(at: url) }
        func createDirectory(at url: URL) throws { try inner.createDirectory(at: url) }
        func listDirectory(at url: URL) throws -> [URL] { try inner.listDirectory(at: url) }

        func readFile(at url: URL) throws -> Data {
            let blocked = lock.withLock {
                readCallCount += 1
                return failReadsWithPermission
            }
            if blocked {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
            }
            return try inner.readFile(at: url)
        }

        func writeProtectedFile(_ data: Data, to url: URL) throws {
            try inner.writeProtectedFile(data, to: url)
        }

        func removeItem(at url: URL) throws {
            let blocked = lock.withLock { failRemoves }
            if blocked {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
            }
            try inner.removeItem(at: url)
        }

        func isPermissionError(_ error: Error) -> Bool { inner.isPermissionError(error) }
        func isNotFoundError(_ error: Error) -> Bool { inner.isNotFoundError(error) }
    }

    /// Paged synthetic school source for `CardRecordsLoader` disk integration tests.
    private actor FakeSchool {
        var rows: [CardRecord]
        var queries: [CardHistoryQuery] = []
        var failAll = false
        var holdFirstRange = false
        var waiting: [CheckedContinuation<Void, Never>] = []
        let today: String

        init(rows: [CardRecord], today: String) {
            self.rows = rows
            self.today = today
        }

        func setRows(_ newRows: [CardRecord]) { rows = newRows }
        func setFail(_ fail: Bool) { failAll = fail }
        func setHold(_ hold: Bool) { holdFirstRange = hold }
        func clearQueries() { queries = [] }
        var isWaiting: Bool { !waiting.isEmpty }
        func release() {
            holdFirstRange = false
            waiting.forEach { $0.resume() }
            waiting.removeAll()
        }

        func page(_ query: CardHistoryQuery) async throws -> CardRecordPage {
            queries.append(query)
            if holdFirstRange && query.end == today {
                await withCheckedContinuation { waiting.append($0) }
            }
            if failAll { throw ServiceError.offline }
            let sorted = rows.sorted { ($0.date, $0.time) > ($1.date, $1.time) }
            return SampleData.recordPage(sorted, query)
        }
    }

    @MainActor
    private func waitSettled(_ loader: CardRecordsLoader, file: StaticString = #filePath, line: UInt = #line) async {
        var quiet = 0
        for _ in 0..<2000 {
            quiet = (!loader.state.reloading && !loader.state.loadingMore) ? quiet + 1 : 0
            if quiet >= 5 { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("loader did not settle", file: file, line: line)
    }

    @MainActor
    private func waitHeld(_ school: FakeSchool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 {
            if await school.isWaiting { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("school never held first range", file: file, line: line)
    }

    // MARK: - Envelope, Privacy & Pruning

    func testEnvelopeRoundTripExcludesVoucherAndPlaintextIdentifiers() throws {
        let history = makeHistory(ranges: 2)
        let salt = Data(repeating: 0xAB, count: 32)
        let tag = CardHistory.ownerTag(identity: "card:SYNTH_UNION_A", salt: salt)

        let encoded = try XCTUnwrap(history.cacheEnvelope(ownerTag: tag, savedAt: noon))
        let rawText = try XCTUnwrap(String(data: encoded.data, encoding: .utf8))

        // Privacy invariants: zero voucher, zero plaintext identity.
        XCTAssertFalse(rawText.contains("99000000"))
        XCTAssertFalse(rawText.contains("voucher"))
        XCTAssertFalse(rawText.contains("SYNTH_UNION_A"))
        XCTAssertFalse(rawText.contains("2026000001"))

        let decoded = try JSONDecoder().decode(CardHistoryDiskEnvelope.self, from: encoded.data)
        let restored = try XCTUnwrap(CardHistory.fromCacheEnvelope(decoded, now: noon, calendar: cal))
        XCTAssertEqual(restored.today, history.today)
        XCTAssertEqual(restored.readFrom, history.readFrom)
        XCTAssertEqual(restored.records.count, history.records.count)
        XCTAssertTrue(restored.records.allSatisfy { $0.voucher == nil })
        XCTAssertEqual(restored.nextQuery, history.nextQuery)
    }

    func testEnvelopeEnforces210DayWindowAndByteBudgetAnd30DayAgeLimit() throws {
        // 17 ranges = 238 days (> 210 days).
        let big = makeHistory(ranges: 17, reachedEnd: true)
        let tag = CardHistory.ownerTag(identity: "card:SYNTH_UNION_A", salt: Data(repeating: 0x11, count: 32))

        // 210-day write pruning shrinks `readFrom` and forces `reachedEnd = false`.
        let encoded = try XCTUnwrap(big.cacheEnvelope(ownerTag: tag, savedAt: noon))
        XCTAssertEqual(encoded.envelope.readFrom, id(back: 209))
        XCTAssertFalse(encoded.envelope.reachedEnd)
        XCTAssertTrue(encoded.envelope.records.allSatisfy { $0.date >= id(back: 209) })

        // 210-day read pruning also enforces the window on an older envelope.
        var unpruned = encoded.envelope
        unpruned.readFrom = id(back: 225)
        unpruned.reachedEnd = true
        let readBack = try XCTUnwrap(CardHistory.fromCacheEnvelope(unpruned, now: noon, calendar: cal))
        XCTAssertEqual(readBack.readFrom, id(back: 209))
        XCTAssertFalse(readBack.reachedEnd)

        // 30-day open age limit rejects stale cache.
        let thirtyOneDaysLater = noon.addingTimeInterval(31 * 24 * 3600)
        XCTAssertNil(CardHistory.fromCacheEnvelope(encoded.envelope, now: thirtyOneDaysLater, calendar: cal))

        // Byte budget trimming drops older days forward until within maxBytes and sets reachedEnd = false.
        let smallBudget = try XCTUnwrap(big.cacheEnvelope(ownerTag: tag, savedAt: noon, maxDays: 210, maxBytes: 2_000))
        XCTAssertLessThanOrEqual(smallBudget.data.count, 2_000)
        XCTAssertFalse(smallBudget.envelope.reachedEnd)
        XCTAssertGreaterThan(smallBudget.envelope.readFrom, id(back: 209))
        XCTAssertFalse(smallBudget.envelope.records.isEmpty)
    }

    func testEnvelopeSkipsHalfPagesAndPrefilledRecords() {
        var partial = CardHistory(now: noon, calendar: cal)
        let home = CardActivity(records: [makeRecord(id(back: 0))], begin: id(back: 6), end: id(back: 0), complete: true)
        partial.prefill(home)
        XCTAssertNil(partial.cacheEnvelope(ownerTag: "tag", savedAt: noon), "prefill-only history must not persist")

        // Receive 1 non-final page (50 rows with total 100): `holdsFirstRange` is still false.
        let q = partial.nextQuery!
        let rows = (0..<50).map { makeRecord(id(back: 0), time: String(format: "%06d", 120000 + $0), voucher: "P\($0)") }
        partial.receive(CardRecordPage(total: 100, rows: rows), for: q)
        XCTAssertFalse(partial.holdsFirstRange)
        XCTAssertNil(partial.cacheEnvelope(ownerTag: "tag", savedAt: noon), "half-read range must not persist")
    }

    // MARK: - Sample Mode, Uncommitted Epochs & Unconfirmed Identity

    func testSampleModeNeverTouchesDiskOrKeychain() async throws {
        let store = InMemorySecureStore()
        try seedCommittedSession(store: store, epochID: "E-SAMPLE")
        let coordinator = CardHistoryDiskCoordinator(store: store, rootDirectory: nil)

        await coordinator.save(makeHistory(ranges: 1), savedAt: noon, samePerson: { true })
        XCTAssertNil(try store.read(.cardHistorySession))
        let loaded = await coordinator.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNil(loaded)
    }

    func testUncommittedEpochsNeverReadWriteOrMintAnchor() async throws {
        let root = makeTempRoot()
        for phase in [SessionEpoch.Phase.switching, .signedOutPendingClear, .signedOut] {
            let store = InMemorySecureStore()
            try seedCommittedSession(store: store, epochID: "E-\(phase.rawValue)", phase: phase)
            let coordinator = CardHistoryDiskCoordinator(store: store, rootDirectory: root)
            await coordinator.save(makeHistory(ranges: 1), savedAt: noon, samePerson: { true })
            XCTAssertNil(try store.read(.cardHistorySession), "phase \(phase) must not mint anchor")
            let loaded = await coordinator.load(now: noon, calendar: cal, samePerson: { true })
            XCTAssertNil(loaded, "phase \(phase) must not load")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testUnconfirmedFallbackIdentityNeverPersists() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        try seedCommittedSession(store: store, epochID: "E-FALLBACK", unionID: "FALLBACK_ID",
                                 account: nil, cardIsFallback: true)
        let coordinator = CardHistoryDiskCoordinator(store: store, rootDirectory: root)
        await coordinator.save(makeHistory(ranges: 1), savedAt: noon, samePerson: { true })
        XCTAssertNil(try store.read(.cardHistorySession))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    // MARK: - Lock-Screen Resilience

    func testLockScreenKeychainAndFilePermissionErrorsNeverDeleteDataOrMintNewSalt() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        let fs = FaultyFileSystem()
        let s1 = "00000000-0000-4000-8000-000000000001"
        try seedCommittedSession(store: store, epochID: "E1")
        let coordinator = CardHistoryDiskCoordinator(store: store, rootDirectory: root, fileSystem: fs,
                                                     makeSessionID: { s1 })
        await coordinator.save(makeHistory(ranges: 2), savedAt: noon, samePerson: { true })
        let originalAnchor = try XCTUnwrap(try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession))
        let fileURL = root.appendingPathComponent("\(s1)/cache.v1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // 1. Keychain locked (-25308) on `cardHistory.session`: load, save, and sweep must not delete or mint.
        store.failReads(from: .cardHistorySession, true)
        let lockedLoad = await coordinator.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNil(lockedLoad)
        await coordinator.save(makeHistory(ranges: 1), savedAt: noon, samePerson: { true })
        await coordinator.sweepOrphans()
        store.failReads(from: .cardHistorySession, false)

        XCTAssertEqual(try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession), originalAnchor)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // 2. File locked (`EPERM`): load returns nil without deleting file or anchor.
        fs.failReadsWithPermission = true
        let fileLockedLoad = await coordinator.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNil(fileLockedLoad)
        fs.failReadsWithPermission = false

        XCTAssertEqual(try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession), originalAnchor)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // 3. Unlocked again: original cache loads intact.
        let recovered = await coordinator.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.sessionID, s1)
    }

    /// Thread-safe counter for deterministic canonical UUID session IDs across `@Sendable` closures.
    private final class SessionCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> String {
            lock.withLock {
                count += 1
                return Self.id(count)
            }
        }
        static func id(_ index: Int) -> String {
            String(format: "00000000-0000-4000-8000-%012d", index)
        }
    }

    /// Async gate for pausing a background coordinator write deterministically without capturing `XCTestCase`.
    private actor WriteGate {
        private var entered = false
        private var enterWaiters: [CheckedContinuation<Void, Never>] = []
        private var released = false
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func enterAndWait() async {
            entered = true
            enterWaiters.forEach { $0.resume() }
            enterWaiters.removeAll()
            if !released {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
        }

        func waitUntilEntered() async {
            if !entered {
                await withCheckedContinuation { enterWaiters.append($0) }
            }
        }

        func release() {
            released = true
            releaseWaiters.forEach { $0.resume() }
            releaseWaiters.removeAll()
        }
    }

    // MARK: - Revo #2: Anchor-Delete-Failure + A -> B -> A + Late Stale Task Isolation

    func testAnchorDeleteFailureAcrossABAColdRestartNeverReopensOldSessionAndProtectsNewSession() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        let counter = SessionCounter()
        let nextSessionID: @Sendable () -> String = { counter.next() }

        let s1 = SessionCounter.id(1)
        let s2 = SessionCounter.id(2)
        let s3 = SessionCounter.id(3)

        // 1. A(E1) saves synthetic records into CardHistory/<s1>/cache.v1.json with anchor (E1, s1, K1).
        try seedCommittedSession(store: store, epochID: "E1", unionID: "SYNTH_UNION_A", account: "2026000001")
        let coord1 = CardHistoryDiskCoordinator(store: store, rootDirectory: root, makeSessionID: nextSessionID)
        await coord1.save(makeHistory(ranges: 2, titlePrefix: "POS消费旧账号A"), savedAt: noon, samePerson: { true })

        let s1Anchor = try XCTUnwrap(try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession))
        XCTAssertEqual(s1Anchor.epochID, "E1")
        XCTAssertEqual(s1Anchor.sessionID, s1)
        let s1File = root.appendingPathComponent("\(s1)/cache.v1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: s1File.path))

        // 2. Switch A -> B(E2) while deleting `cardHistory.session` fails (e.g. lock-screen failure).
        try seedCommittedSession(store: store, epochID: "E2", unionID: "SYNTH_UNION_B", account: "2026000002")
        store.failWrites(to: .cardHistorySession, true)
        await coord1.invalidateStaleSession()
        // Anchor is STILL (E1, s1, K1) because Keychain delete failed.
        XCTAssertEqual(try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession), s1Anchor)

        // 3. Switch B -> A(E3), then cold restart (fresh coordinator) while delete still fails.
        try seedCommittedSession(store: store, epochID: "E3", unionID: "SYNTH_UNION_A", account: "2026000001")
        let coordRestarted = CardHistoryDiskCoordinator(store: store, rootDirectory: root, makeSessionID: nextSessionID)

        // Even though `ownerTag` still matches A, `E1 != E3` MUST block opening s1 (zero-frame display).
        let staleLoad = await coordRestarted.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNil(staleLoad, "old epoch anchor must never reopen S1 after A->B->A")

        // While deleting the old anchor still fails, save stays strictly memory-only and NEVER writes s1.
        let s1BytesBefore = try? Data(contentsOf: s1File)
        await coordRestarted.save(makeHistory(ranges: 1, titlePrefix: "POS消费新A"), savedAt: noon, samePerson: { true })
        XCTAssertEqual(try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession), s1Anchor)
        if let s1BytesBefore {
            XCTAssertEqual(try? Data(contentsOf: s1File), s1BytesBefore)
        }

        // 4. Restore Keychain write/delete permission: fresh save mints brand-new (E3, s2, K2) and sweeps s1.
        store.failWrites(to: .cardHistorySession, false)
        await coordRestarted.save(makeHistory(ranges: 2, titlePrefix: "POS消费新会话A"), savedAt: noon, samePerson: { true })
        let newAnchor = try XCTUnwrap(try store.readJSON(CardHistorySessionAnchor.self, .cardHistorySession))
        XCTAssertEqual(newAnchor.epochID, "E3")
        XCTAssertEqual(newAnchor.sessionID, s2)
        XCTAssertNotEqual(newAnchor.salt, s1Anchor.salt)
        let s2File = root.appendingPathComponent("\(s2)/cache.v1.json")
        let s2Bytes = try Data(contentsOf: s2File)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(s1).path),
                       "old session directory S1 must be swept")

        // 5. Verify a late stale task paused from an earlier session never deletes or mutates s3.
        let gate = WriteGate()
        let lateCoord = CardHistoryDiskCoordinator(store: store, rootDirectory: root, makeSessionID: nextSessionID)
        await lateCoord.setHooks(beforeWriteFile: { _, _ in
            await gate.enterAndWait()
        })
        let lateHistory = makeHistory(ranges: 1, titlePrefix: "POS消费迟到旧写入")
        let lateNoon = noon
        let lateTask = Task {
            await lateCoord.save(lateHistory, savedAt: lateNoon, samePerson: { true })
        }
        await gate.waitUntilEntered()
        // Advance epoch to E4 and mint s3 before releasing the paused E3/s2 write.
        try seedCommittedSession(store: store, epochID: "E4", unionID: "SYNTH_UNION_B", account: "2026000002")
        let coordE4 = CardHistoryDiskCoordinator(store: store, rootDirectory: root, makeSessionID: nextSessionID)
        await coordE4.save(makeHistory(ranges: 1, titlePrefix: "POS消费账号B最新"), savedAt: noon, samePerson: { true })
        let s3File = root.appendingPathComponent("\(s3)/cache.v1.json")
        let s3BytesBefore = try Data(contentsOf: s3File)

        await gate.release()
        await lateTask.value
        XCTAssertEqual(try Data(contentsOf: s3File), s3BytesBefore, "late task must not overwrite or delete S3")
        XCTAssertNotEqual(s2Bytes, s3BytesBefore)
    }

    func testCleanupFailureIsolatesOldDirectoryAndUnlockSweepRemovesIt() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        let fs = FaultyFileSystem()
        let oldSession = UUID().uuidString
        try seedCommittedSession(store: store, epochID: "E1")
        let coordinator = CardHistoryDiskCoordinator(store: store, rootDirectory: root, fileSystem: fs,
                                                     makeSessionID: { oldSession })
        await coordinator.save(makeHistory(ranges: 1), savedAt: noon, samePerson: { true })
        let oldDir = root.appendingPathComponent(oldSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldDir.path))

        // Sign out while directory removal fails: anchor is deleted immediately so data is invisible.
        fs.failRemoves = true
        try SessionEpochStore(store: store).write(SessionEpoch(id: "E2", phase: .signedOut))
        await coordinator.invalidateAndClear()
        XCTAssertNil(try store.read(.cardHistorySession))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldDir.path), "directory deletion failed as injected")

        // Signed-out load returns nil; new session E3 load returns nil (never sees S-OLD).
        let signedOutLoaded = await coordinator.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNil(signedOutLoaded)
        try seedCommittedSession(store: store, epochID: "E3", unionID: "SYNTH_UNION_B", account: "2026000002")
        let newAccountLoaded = await coordinator.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNil(newAccountLoaded)

        // Restore FS removal permission -> unlock sweep removes orphan directory cleanly.
        fs.failRemoves = false
        await coordinator.sweepOrphans()
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDir.path))
    }

    // MARK: - CardRecordsLoader Disk Integration

    @MainActor
    func testColdRestartHydratesFromDiskCatchesUp14DaysAndPullOverwritesCache() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        try seedCommittedSession(store: store, epochID: "E1")
        let disk = CardHistoryDiskCoordinator(store: store, rootDirectory: root)

        let day40 = id(back: 40)
        let rows = (0..<70).map { makeRecord(id(back: $0), yuan: "10.00", voucher: "V\($0)") }
        let school = FakeSchool(rows: rows, today: id(back: 0))

        // 1. First launch: loads 60 days, persists to disk.
        let source1 = CardRecordsSource(stamp: { 1 }, page: { query, _ in try await school.page(query) },
                                        memory: CardRecordsMemory(), diskCache: disk)
        let loader1 = CardRecordsLoader(source: source1, now: { [noon] in noon })
        loader1.setTarget(id(back: 59))
        await loader1.reload()
        await waitSettled(loader1)
        XCTAssertTrue(loader1.state.history?.hasRead(through: id(back: 59)) ?? false)

        // 2. Cold restart (brand-new empty CardRecordsMemory): hydrates from disk immediately and fetches only 14d.
        let newToday = makeRecord(id(back: 0), yuan: "5.00", time: "160000", voucher: "V-NEW")
        let correctedDay40 = makeRecord(day40, yuan: "22.00", time: "120000", voucher: "V-CORR")
        await school.setRows(rows.filter { $0.date != day40 } + [newToday, correctedDay40])
        await school.clearQueries()
        await school.setHold(true)

        let source2 = CardRecordsSource(stamp: { 1 }, page: { query, _ in try await school.page(query) },
                                        memory: CardRecordsMemory(), diskCache: disk)
        let loader2 = CardRecordsLoader(source: source2, now: { [noon] in noon })
        loader2.setTarget(id(back: 59))
        let openTask = Task { await loader2.reload() }
        await waitHeld(school)
        XCTAssertEqual(loader2.state.phase, .loaded, "hydrated immediately from disk cache")
        XCTAssertTrue(loader2.state.history?.hasRead(through: id(back: 59)) ?? false)

        await school.release()
        await openTask.value
        await waitSettled(loader2)

        let autoQueries = await school.queries
        XCTAssertEqual(autoQueries.count, 1, "cold launch only catches up newest 14-day range")
        XCTAssertEqual(autoQueries.first?.begin, id(back: 13))
        XCTAssertEqual(loader2.state.history?.records.first(where: { $0.date == day40 })?.amount, Money(yuanString: "10.00"),
                       "auto catch-up keeps older cached days without re-fetching them")

        // 3. Explicit pull-to-refresh re-fetches full target from today and overwrites disk cache with correction.
        await school.clearQueries()
        await loader2.reload()
        await waitSettled(loader2)
        let pullQueries = await school.queries
        XCTAssertGreaterThan(pullQueries.count, 1, "pull-to-refresh reloads full span")
        XCTAssertEqual(loader2.state.history?.records.first(where: { $0.date == day40 })?.amount, Money(yuanString: "22.00"))

        // 4. Subsequent cold restart reads the corrected value from disk.
        let reloadedEntry = await disk.load(now: noon, calendar: cal, samePerson: { true })
        let reloadedFromDisk = try XCTUnwrap(reloadedEntry)
        XCTAssertEqual(reloadedFromDisk.history.records.first(where: { $0.date == day40 })?.amount, Money(yuanString: "22.00"))
    }

    @MainActor
    func testGappedDiskCacheDiscardsGapWhenOnlineAndShowsCutoffWhenOffline() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        try seedCommittedSession(store: store, epochID: "E1")
        let disk = CardHistoryDiskCoordinator(store: store, rootDirectory: root)

        // Cached 20 days ago (<= 30 days age, but > 14 days gap so no date overlap with today's 14d range).
        let twentyDaysAgo = cal.date(byAdding: .day, value: -20, to: noon)!
        let oldHistory = makeHistory(ranges: 2, base: twentyDaysAgo)
        await disk.save(oldHistory, savedAt: twentyDaysAgo, samePerson: { true })

        let allRows = (0..<70).map { makeRecord(id(back: $0), yuan: "10.00", voucher: "G\($0)") }

        // 1. Offline visit: shows old cached history with refreshFailed = true and original savedAt.
        let offlineSchool = FakeSchool(rows: allRows, today: id(back: 0))
        await offlineSchool.setFail(true)
        let offlineLoader = CardRecordsLoader(
            source: CardRecordsSource(stamp: { 1 }, page: { q, _ in try await offlineSchool.page(q) },
                                      memory: CardRecordsMemory(), diskCache: disk),
            now: { [noon] in noon }
        )
        offlineLoader.setTarget(id(back: 29))
        await offlineLoader.reload()
        await waitSettled(offlineLoader)
        XCTAssertEqual(offlineLoader.state.phase, .loaded)
        XCTAssertTrue(offlineLoader.state.refreshFailed)
        XCTAssertEqual(offlineLoader.state.history?.today, cal.startOfDay(for: twentyDaysAgo))
        XCTAssertEqual(offlineLoader.state.cachedSavedAt, twentyDaysAgo)

        // 2. Online visit: no date overlap -> discards gapped cache and fetches back cleanly without zero-filling.
        let onlineSchool = FakeSchool(rows: allRows, today: id(back: 0))
        let onlineLoader = CardRecordsLoader(
            source: CardRecordsSource(stamp: { 1 }, page: { q, _ in try await onlineSchool.page(q) },
                                      memory: CardRecordsMemory(), diskCache: disk),
            now: { [noon] in noon }
        )
        onlineLoader.setTarget(id(back: 29))
        await onlineLoader.reload()
        await waitSettled(onlineLoader)
        XCTAssertFalse(onlineLoader.state.refreshFailed)
        XCTAssertEqual(onlineLoader.state.history?.today, cal.startOfDay(for: noon))
        let queries = await onlineSchool.queries
        XCTAssertGreaterThanOrEqual(queries.count, 3, "gapped cache must fetch back continuously through target")
        XCTAssertTrue(onlineLoader.state.history?.hasRead(through: id(back: 29)) ?? false)
    }

    // MARK: - SpendStats Cross-Day Offline Anchoring

    func testSpendStatsAnchoredOnEarlierCachedDayOmitsTodayAndThisWeekLabels() throws {
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: noon)! // Sunday 2026-11-22
        let history = makeHistory(ranges: 7, base: twoDaysAgo)
        let termStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!

        let week = try XCTUnwrap(SpendStats.make(span: .week, history: history, termStart: termStart,
                                                 calendar: cal, now: noon))
        XCTAssertEqual(week.bars.last?.id, "20261122")
        XCTAssertEqual(week.bars.last?.isCurrent, false)
        XCTAssertEqual(week.bars.last?.axisLabel, "日")

        let month = try XCTUnwrap(SpendStats.make(span: .month, history: history, termStart: termStart,
                                                  calendar: cal, now: noon))
        XCTAssertEqual(month.bars.last?.id, "20261122")
        XCTAssertEqual(month.bars.last?.isCurrent, false)
        XCTAssertEqual(month.bars.last?.axisLabel, "11月22日")

        let term = try XCTUnwrap(SpendStats.make(span: .term, history: history, termStart: termStart,
                                                 calendar: cal, now: noon))
        XCTAssertEqual(term.bars.last?.isCurrent, false)
        XCTAssertEqual(term.bars.last?.axisLabel, "11月22日")
        XCTAssertNotEqual(term.bars.last?.axisLabel, "本周")
    }

    // MARK: - Round 2 Review Fixes (Revo #3, #4, #5)

    /// Revo #4 (a): reading older pages at 12:00 must update `savedAt` (file write time) without
    /// bumping `latestReadAt` (08:30, when the newest 14-day range was actually read from school).
    @MainActor
    func testLoadMoreOlderPagesDoesNotBumpLatestReadAt() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        try seedCommittedSession(store: store, epochID: "E1")
        let disk = CardHistoryDiskCoordinator(store: store, rootDirectory: root)

        let at0830 = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 8, minute: 30))!
        let at1200 = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12, minute: 0))!
        let at1215 = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12, minute: 15))!

        var clock = at0830
        let allRows = (0..<60).map { makeRecord(id(back: $0, from: at0830), yuan: "10.00", voucher: "T\($0)") }
        let school = FakeSchool(rows: allRows, today: id(back: 0, from: at0830))
        let memory = CardRecordsMemory()
        let loader = CardRecordsLoader(
            source: CardRecordsSource(stamp: { 1 }, page: { q, _ in try await school.page(q) },
                                      memory: memory, diskCache: disk),
            now: { clock }
        )

        // 08:30: read newest 14-day range only.
        await loader.reload()
        await waitSettled(loader)
        XCTAssertEqual(loader.state.cachedLatestReadAt, at0830)
        XCTAssertEqual(loader.state.cachedSavedAt, at0830)

        // 12:00: load older pages (last month) without re-reading today's range.
        clock = at1200
        await loader.read(through: id(back: 45, from: at0830))
        await waitSettled(loader)
        XCTAssertEqual(loader.state.cachedSavedAt, at1200, "file write time updated to 12:00")
        XCTAssertEqual(loader.state.cachedLatestReadAt, at0830, "newest-range read time stays 08:30")

        // 12:15: cold restart offline -> must report latestReadAt = 08:30, NOT 12:00.
        clock = at1215
        await school.setFail(true)
        let coldLoader = CardRecordsLoader(
            source: CardRecordsSource(stamp: { 1 }, page: { q, _ in try await school.page(q) },
                                      memory: CardRecordsMemory(), diskCache: disk),
            now: { clock }
        )
        await coldLoader.reload()
        await waitSettled(coldLoader)
        XCTAssertTrue(coldLoader.state.refreshFailed)
        XCTAssertEqual(coldLoader.state.cachedLatestReadAt, at0830)
        XCTAssertEqual(coldLoader.state.cachedSavedAt, at1200)
    }

    /// Revo #4 (b): a short final page where `rows.count < expectedRemaining` marks the affected
    /// days unsure and preserves that unsure state across disk save + reload (no fake day total).
    func testShortFinalPageUnsureStatePersistsAcrossDiskRoundTrip() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        try seedCommittedSession(store: store, epochID: "E1")
        let disk = CardHistoryDiskCoordinator(store: store, rootDirectory: root)

        var history = CardHistory(now: noon, calendar: cal)
        let q1 = history.nextQuery!
        var p1Rows: [CardRecord] = []
        for i in 0..<50 {
            let day = i < 30 ? id(back: 0) : id(back: 1)
            p1Rows.append(makeRecord(day, yuan: "5.00", time: String(format: "%06d", 200000 - i), voucher: "P1-\(i)"))
        }
        history.receive(CardRecordPage(total: 65, rows: p1Rows), for: q1)
        let q2 = try XCTUnwrap(history.nextQuery)
        let cutDay = id(back: 5)
        let p2Rows = (0..<10).map { i in
            makeRecord(cutDay, yuan: "6.00", time: String(format: "%06d", 120000 - i), voucher: "P2-\(i)")
        }
        // School reports total = 65 (15 remaining expected), returns only 10 rows.
        history.receive(CardRecordPage(total: 65, rows: p2Rows), for: q2)
        XCTAssertFalse(history.isComplete(day: cutDay))

        await disk.save(history, savedAt: noon, latestReadAt: noon, samePerson: { true })
        let loadedRaw = await disk.load(now: noon, calendar: cal, samePerson: { true })
        let loaded = try XCTUnwrap(loadedRaw)
        XCTAssertFalse(loaded.history.isComplete(day: cutDay), "short final page remains unsure after disk reload")
        let groups = CardDays.groups(history: loaded.history, app: [], now: noon)
        XCTAssertNil(groups.first(where: { $0.id == cutDay })?.total, "incomplete cached day must not show a total")
    }

    /// Revo #5 (a): malformed/path-traversal anchor `sessionID` is rejected on decode/validation
    /// and never touches sibling files during load or cleanup.
    func testMalformedAnchorSessionIDDoesNotTouchSiblingFiles() async throws {
        let store = InMemorySecureStore()
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xrc-anchor-safety-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: baseDir) }
        let root = baseDir.appendingPathComponent("CardHistory", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sibling = baseDir.appendingPathComponent("sibling-keep.txt")
        try Data("do-not-delete".utf8).write(to: sibling)
        try seedCommittedSession(store: store, epochID: "E1")

        // Write a malformed anchor attempting path traversal outside CardHistory root.
        let badAnchor = CardHistorySessionAnchor(epochID: "E1", sessionID: "../sibling-keep.txt",
                                                 salt: Data(repeating: 0xAA, count: 32))
        XCTAssertFalse(badAnchor.isValid)
        try store.write(try JSONEncoder().encode(badAnchor), for: .cardHistorySession)

        let disk = CardHistoryDiskCoordinator(store: store, rootDirectory: root)
        let loaded = await disk.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNil(loaded, "malformed anchor must be rejected")
        await disk.invalidateStaleSession()
        await disk.invalidateAndClear()
        await disk.sweepOrphans()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path), "sibling file must remain untouched")
        XCTAssertEqual(try Data(contentsOf: sibling), Data("do-not-delete".utf8))
    }

    /// Revo #5 (b): opening a 210-day disk cache 10 days later trims the oldest 10 days that now
    /// fall outside the 210-day window anchored on the open day.
    func testOpeningDiskCacheTenDaysLaterTrimsOldestTenDays() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        try seedCommittedSession(store: store, epochID: "E1")
        let disk = CardHistoryDiskCoordinator(store: store, rootDirectory: root)

        // 15 ranges = 210 days ending on `noon`.
        let full210 = makeHistory(ranges: 15, base: noon)
        XCTAssertEqual(full210.readFrom, id(back: 209, from: noon))
        await disk.save(full210, savedAt: noon, latestReadAt: noon, samePerson: { true })

        let tenDaysLater = cal.date(byAdding: .day, value: 10, to: noon)!
        let loadedRaw = await disk.load(now: tenDaysLater, calendar: cal, samePerson: { true })
        let loaded = try XCTUnwrap(loadedRaw)

        let expectedCutoff = id(back: 209, from: tenDaysLater) // = id(back: 199, from: noon)
        XCTAssertEqual(loaded.history.readFrom, expectedCutoff, "oldest 10 days beyond 210d from open day must be trimmed")
        XCTAssertTrue(loaded.history.records.allSatisfy { $0.date >= expectedCutoff })
        XCTAssertFalse(loaded.history.records.contains { $0.date == id(back: 209, from: noon) })
        XCTAssertFalse(loaded.history.records.contains { $0.date == id(back: 200, from: noon) })
        XCTAssertTrue(loaded.history.records.contains { $0.date == id(back: 199, from: noon) })
    }

    /// Revo #5 (c): an on-disk cache file exceeding 1 MiB is rejected by file-size check BEFORE
    /// reading its bytes into memory or decoding JSON.
    func testOversizedDiskCacheOver1MiBIsRejectedBeforeReading() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        let fs = FaultyFileSystem()
        try seedCommittedSession(store: store, epochID: "E1")
        let disk = CardHistoryDiskCoordinator(store: store, rootDirectory: root, fileSystem: fs)

        // Seed valid session & small cache first so anchor exists.
        await disk.save(makeHistory(ranges: 1, base: noon), savedAt: noon, latestReadAt: noon, samePerson: { true })
        let anchorData = try XCTUnwrap(try store.read(.cardHistorySession))
        let anchor = try JSONDecoder().decode(CardHistorySessionAnchor.self, from: anchorData)
        let cacheURL = root.appendingPathComponent(anchor.sessionID, isDirectory: true)
            .appendingPathComponent("cache.v1.json")

        // Overwrite with > 1 MiB payload.
        try Data(repeating: 0x20, count: CardHistory.maxCacheBytes + 1).write(to: cacheURL)
        fs.readCallCount = 0

        let loaded = await disk.load(now: noon, calendar: cal, samePerson: { true })
        XCTAssertNil(loaded, "oversized cache file must be rejected")
        XCTAssertEqual(fs.readCallCount, 0, "fileSize guard must reject before reading bytes into memory")
    }

    /// Revo #3: A's late disk-cache load / offline refresh failure returning after B's reload
    /// started must never overwrite B's loaded state or set `refreshFailed` on B.
    @MainActor
    func testLateDiskOfflineFailureForADoesNotOverwriteB() async throws {
        let store = InMemorySecureStore()
        let root = makeTempRoot()
        try seedCommittedSession(store: store, epochID: "E1", unionID: "SYNTH_UNION_A")
        let disk = CardHistoryDiskCoordinator(store: store, rootDirectory: root)
        let aHistory = makeHistory(ranges: 1, base: noon, titlePrefix: "POS消费A窗口")
        await disk.save(aHistory, savedAt: noon, latestReadAt: noon, samePerson: { true })

        actor SwitchedSchool {
            var currentPerson = 1
            var waitingA: CheckedContinuation<Void, Never>?
            var aRows: [CardRecord]
            var bRows: [CardRecord]
            init(a: [CardRecord], b: [CardRecord]) { aRows = a; bRows = b }
            func stamp() -> Int { currentPerson }
            func isSame(_ s: Int) -> Bool { currentPerson == s }
            func switchToB() { currentPerson = 2 }
            func releaseA() { waitingA?.resume(); waitingA = nil }
            func isAHolding() -> Bool { waitingA != nil }
            func page(_ q: CardHistoryQuery, stamp: Int) async throws -> CardRecordPage {
                if stamp == 1 {
                    await withCheckedContinuation { waitingA = $0 }
                    throw ServiceError.offline
                }
                return SampleData.recordPage(bRows, q)
            }
        }

        let bRow = makeRecord(id(back: 0), yuan: "9.90", title: "POS消费B食堂", voucher: "B-1")
        let school = SwitchedSchool(a: aHistory.records, b: [bRow])
        let memory = CardRecordsMemory()
        let loader = CardRecordsLoader(
            source: CardRecordsSource(stamp: { await school.stamp() },
                                      page: { q, s in try await school.page(q, stamp: s) },
                                      samePerson: { await school.isSame($0) },
                                      memory: memory, diskCache: disk),
            now: { [noon] in noon }
        )

        // A starts visiting (hydrates A's disk cache and hangs on newest-range network refresh).
        let aVisit = Task { await loader.reload() }
        for _ in 0..<2000 {
            if await school.isAHolding() { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let held = await school.isAHolding()
        XCTAssertTrue(held)

        // B signs in and starts reload while A is still in flight.
        await school.switchToB()
        await loader.reload()
        await waitSettled(loader)
        XCTAssertEqual(loader.state.phase, .loaded)
        XCTAssertFalse(loader.state.refreshFailed)
        XCTAssertEqual(loader.state.history?.records, [bRow])

        // Now A's held offline failure returns late.
        await school.releaseA()
        await aVisit.value
        await waitSettled(loader)

        // B's state must remain intact: no A rows, no refreshFailed.
        XCTAssertEqual(loader.state.phase, .loaded)
        XCTAssertFalse(loader.state.refreshFailed)
        XCTAssertEqual(loader.state.history?.records, [bRow])
    }
}
