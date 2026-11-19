import XCTest
@testable import Core

/// 校园卡记录's reads: a pull while older pages load, reads that come back late, and which
/// failures leave rows on the page.
@MainActor final class CardRecordsLoaderTests: XCTestCase {
    let cal = SchoolCalendar.shanghai
    /// 2026-10-30 12:00 in Shanghai.
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))! }
    nonisolated static let today = "20261030"

    nonisolated static func record(_ date: String, _ time: String, _ yuan: String = "12.00") -> CardRecord {
        CardRecord(date: date, time: time, title: "POS消费示例面馆", amount: Money(yuanString: yuan)!,
                   balanceAfter: nil, direction: "1")
    }

    func makeLoader(_ school: School) -> CardRecordsLoader {
        CardRecordsLoader(source: CardRecordsSource(stamp: { await school.nextStamp() },
                                                    page: { query, stamp in try await school.page(query, stamp: stamp) },
                                                    samePerson: { await school.isPerson($0) },
                                                    renew: { await school.renew() }),
                          now: { [noon] in noon })
    }

    /// The school, scripted: today's range answers with `todayRows`, older ranges with
    /// `olderRows`; a read waits while its key is held ("today" / "older").
    actor School {
        var todayRows: [CardRecord]
        var olderRows: [CardRecord] = []
        var failToday = false
        var failOlder = false
        var held: Set<String> = []
        var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
        var calls: [(query: CardHistoryQuery, stamp: Int)] = []

        init(today: [CardRecord]) { todayRows = today }

        /// Who is signed in (`SchoolSession.personStamp()`): the same until someone else signs in.
        var person = 1
        func nextStamp() -> Int { person }
        func switchPerson() { person += 1 }
        /// The card session has expired; `renew()` brings a new one when `renewWorks`.
        var expired = false
        var renewWorks = true
        var renewals = 0
        /// What a read with the expired session throws (getRecordList itself does not validate).
        var expiredError = ServiceError.sessionExpired(.ecykt)
        func expire(renewWorks: Bool, as error: ServiceError = .sessionExpired(.ecykt)) {
            expired = true; self.renewWorks = renewWorks; expiredError = error
        }
        var offline = false
        func goOffline() { offline = true }
        func renew() -> Bool { renewals += 1; if renewWorks { expired = false }; return renewWorks }
        func isPerson(_ stamp: Int) -> Bool { person == stamp }
        func set(today: [CardRecord]) { todayRows = today }
        func set(older: [CardRecord]) { olderRows = older }
        func set(failToday: Bool, failOlder: Bool) { self.failToday = failToday; self.failOlder = failOlder }
        func hold(_ key: String) { held.insert(key) }
        func release(_ key: String) {
            held.remove(key)
            for c in waiting.removeValue(forKey: key) ?? [] { c.resume() }
        }
        func isWaiting(_ key: String) -> Bool { !(waiting[key] ?? []).isEmpty }
        func olderCalls() -> Int { calls.filter { $0.query.end != CardRecordsLoaderTests.today }.count }
        func stampsUsed() -> [Int] { calls.map(\.stamp) }

        func page(_ query: CardHistoryQuery, stamp: Int) async throws -> CardRecordPage {
            calls.append((query, stamp))
            // As SchoolSession.cardHistoryPage: nothing for a person no longer signed in.
            if stamp != person { throw ServiceError.sessionExpired(.ecykt) }
            if offline { throw ServiceError.offline }
            if expired { throw expiredError }
            let key = query.end == CardRecordsLoaderTests.today ? "today" : "older"
            if held.contains(key) { await withCheckedContinuation { waiting[key, default: []].append($0) } }
            if key == "today" {
                if failToday { throw ServiceError.offline }
                return CardRecordPage(total: todayRows.count, rows: todayRows)
            }
            if failOlder { throw ServiceError.offline }
            let rows = olderRows.filter { $0.date >= query.begin && $0.date <= query.end }
            return CardRecordPage(total: rows.count, rows: rows)
        }
    }

    func waitUntil(_ school: School, waitingOn key: String, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 {
            if await school.isWaiting(key) { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("nothing waited on \(key)", file: file, line: line)
    }

    func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    // MARK: A pull while older pages load

    /// The list's end appears while a pull reads from today: no older page is asked for the
    /// list being replaced, and the pulled list is what stays.
    func testNoOlderPageIsReadWhileAPullRuns() async {
        let first = Self.record(Self.today, "090000")
        let school = School(today: [first])
        await school.set(older: [Self.record("20261010", "120000")])
        let loader = makeLoader(school)
        await loader.reload()
        XCTAssertEqual(loader.state.history?.records, [first])

        let pulled = Self.record(Self.today, "110000")
        await school.set(today: [pulled, first])
        await school.hold("today")
        let pull = Task { await loader.reload() }
        await waitUntil(school, waitingOn: "today")
        XCTAssertTrue(loader.state.reloading)

        // The end of the old list comes into view meanwhile; an older read would answer late.
        await school.hold("older")
        let more = Task { await loader.loadMore() }
        await settle()
        let olderAsked = await school.olderCalls()
        XCTAssertEqual(olderAsked, 0, "nothing older is read for a list being replaced")

        await school.release("today")
        await pull.value
        await school.release("older")
        await more.value
        XCTAssertEqual(loader.state.history?.records, [pulled, first], "the pulled list is not replaced by the old one")
        XCTAssertFalse(loader.state.loadingMore)
        XCTAssertFalse(loader.state.reloading)
    }

    /// The list's end was already in view when a pull came in: the view cannot see it appear
    /// again, so each pull that comes in is counted (the view renews the end with it), and the
    /// older pages are read from the pulled list.
    func testEachPullThatComesInIsCountedForTheListsEnd() async {
        let first = Self.record(Self.today, "090000")
        let school = School(today: [first])
        let older = Self.record("20261010", "120000")
        await school.set(older: [older])
        let loader = makeLoader(school)
        XCTAssertEqual(loader.state.reloads, 0)
        await loader.reload()
        XCTAssertEqual(loader.state.reloads, 1)

        await school.hold("today")
        let pull = Task { await loader.reload() }
        await waitUntil(school, waitingOn: "today")
        await loader.loadMore()
        XCTAssertEqual(loader.state.reloads, 1, "a pull still running is not counted")
        let olderAsked = await school.olderCalls()
        XCTAssertEqual(olderAsked, 0)
        await school.release("today")
        await pull.value
        XCTAssertEqual(loader.state.reloads, 2)

        await loader.loadMore()
        XCTAssertTrue(loader.state.history?.records.contains(older) ?? false)
    }

    /// An older page asked for before a pull, back after it: dropped, the pulled list stays.
    func testAnOlderPageBackAfterAPullIsDropped() async {
        let first = Self.record(Self.today, "090000")
        let school = School(today: [first])
        await school.set(older: [Self.record("20261010", "120000")])
        let loader = makeLoader(school)
        await loader.reload()

        await school.hold("older")
        let more = Task { await loader.loadMore() }
        await waitUntil(school, waitingOn: "older")
        XCTAssertTrue(loader.state.loadingMore)

        let pulled = Self.record(Self.today, "110000")
        await school.set(today: [pulled])
        await loader.reload()
        await school.release("older")
        await more.value
        XCTAssertEqual(loader.state.history?.records, [pulled])
        XCTAssertFalse(loader.state.loadingMore)
    }

    // MARK: Late reads from today

    /// Two pulls with someone else signing in between: the first one's answer, back last, is
    /// dropped, and older pages are read for the person the kept list was read for.
    func testAnEarlierPullBackLastIsDroppedAndItsStampWithIt() async {
        let early = Self.record(Self.today, "080000")
        let school = School(today: [early])
        let loader = makeLoader(school)
        await school.hold("today")
        let firstPull = Task { await loader.reload() }
        await waitUntil(school, waitingOn: "today")
        await school.switchPerson()

        let late = Self.record(Self.today, "100000")
        await school.set(today: [late])
        await school.release("today")
        await loader.reload()
        await firstPull.value
        XCTAssertEqual(loader.state.history?.records, [late])

        // Whichever answered first, the list is the second pull's (stamp 2) …
        let stampsBefore = await school.stampsUsed()
        XCTAssertEqual(stampsBefore.last, 2)
        // … and the next older page is read with its stamp.
        await school.set(older: [Self.record("20261010", "120000")])
        await loader.loadMore()
        let stamps = await school.stampsUsed()
        XCTAssertEqual(stamps.last, 2)
    }

    // MARK: Failures

    func testAFirstReadThatFailsShowsTheLineAndNoRows() async {
        let school = School(today: [])
        await school.set(failToday: true, failOlder: false)
        let loader = makeLoader(school)
        await loader.reload()
        XCTAssertEqual(loader.state.phase, .failed)
        XCTAssertNil(loader.state.history)
        XCTAssertFalse(loader.state.moreFailed)
    }

    func testAnOlderPageThatFailsKeepsTheRows() async {
        let first = Self.record(Self.today, "090000")
        let school = School(today: [first])
        await school.set(failToday: false, failOlder: true)
        let loader = makeLoader(school)
        await loader.reload()
        await loader.loadMore()
        XCTAssertEqual(loader.state.phase, .loaded)
        XCTAssertEqual(loader.state.history?.records, [first])
        XCTAssertTrue(loader.state.moreFailed)
        XCTAssertFalse(loader.state.loadingMore)

        await school.set(failToday: false, failOlder: false)
        await school.set(older: [Self.record("20261010", "120000")])
        await loader.loadMore()
        XCTAssertFalse(loader.state.moreFailed)
        XCTAssertEqual(loader.state.history?.records.count, 2)
    }

    // MARK: An expired card session

    /// The card session expired since home last read it: it is renewed (as home renews it) and
    /// the page read again, so a pull here recovers by itself.
    func testAnExpiredSessionIsRenewedAndThePageReadAgain() async {
        let row = Self.record(Self.today, "090000")
        let school = School(today: [row])
        await school.expire(renewWorks: true)
        let loader = makeLoader(school)
        await loader.reload()
        XCTAssertEqual(loader.state.phase, .loaded)
        XCTAssertEqual(loader.state.history?.records, [row])
        let renewals = await school.renewals
        XCTAssertEqual(renewals, 1)
    }

    /// getRecordList does not check the session: an expired one answers in its own words
    /// (code -1) or with an empty reply. Either is renewed the same way.
    func testARefusalFromAnExpiredSessionIsRenewedToo() async {
        for error in [ServiceError.rejected(.ecykt, code: "-1", message: "x"), .badRequest(.ecykt)] {
            let row = Self.record(Self.today, "090000")
            let school = School(today: [row])
            await school.expire(renewWorks: true, as: error)
            let loader = makeLoader(school)
            await loader.reload()
            XCTAssertEqual(loader.state.phase, .loaded, "\(error)")
            XCTAssertEqual(loader.state.history?.records, [row], "\(error)")
            let renewals = await school.renewals
            XCTAssertEqual(renewals, 1, "\(error)")
        }
    }

    /// The school refusing in its own words for another reason (a lost card, code 2) says
    /// nothing about the session: nothing is renewed.
    func testAnotherRefusalIsNotRenewed() async {
        let school = School(today: [Self.record(Self.today, "090000")])
        await school.expire(renewWorks: true, as: .rejected(.ecykt, code: "2", message: "x"))
        let loader = makeLoader(school)
        await loader.reload()
        XCTAssertEqual(loader.state.phase, .failed)
        let renewals = await school.renewals
        XCTAssertEqual(renewals, 0)
    }

    /// Offline says nothing about the session: nothing is renewed.
    func testNothingIsRenewedWhenOffline() async {
        let school = School(today: [Self.record(Self.today, "090000")])
        await school.goOffline()
        let loader = makeLoader(school)
        await loader.reload()
        XCTAssertEqual(loader.state.phase, .failed)
        let renewals = await school.renewals
        XCTAssertEqual(renewals, 0)
    }

    func testARenewalThatFailsLeavesTheFailedLineAndIsTriedOnce() async {
        let school = School(today: [Self.record(Self.today, "090000")])
        await school.expire(renewWorks: false)
        let loader = makeLoader(school)
        await loader.reload()
        XCTAssertEqual(loader.state.phase, .failed)
        let renewals = await school.renewals
        XCTAssertEqual(renewals, 1)
    }

    /// Someone else signed in: nothing is renewed for the list read for the one before.
    func testNothingIsRenewedForAPersonNoLongerSignedIn() async {
        let school = School(today: [Self.record(Self.today, "090000")])
        await school.set(older: [Self.record("20261010", "120000")])
        let loader = makeLoader(school)
        await loader.reload()
        await school.switchPerson()
        await loader.loadMore()
        let renewals = await school.renewals
        XCTAssertEqual(renewals, 0)
    }

    // MARK: Another person

    /// Someone else signed in while the list was open: its rows go, and the list is read again
    /// for the person signed in now, instead of offering to retry the old one's older pages.
    func testAnotherPersonSigningInDropsTheListOnTheNextRead() async {
        let theirs = Self.record(Self.today, "090000")
        let school = School(today: [theirs])
        await school.set(older: [Self.record("20261010", "120000")])
        let loader = makeLoader(school)
        await loader.reload()
        XCTAssertEqual(loader.state.history?.records, [theirs])

        await school.switchPerson()
        let mine = Self.record(Self.today, "100000", "3.00")
        await school.set(today: [mine])
        await loader.loadMore()
        XCTAssertFalse(loader.state.moreFailed, "no retry offered for someone else's list")
        XCTAssertEqual(loader.state.history?.records, [mine], "read again for whoever is signed in now")
        XCTAssertFalse(loader.state.history?.records.contains(theirs) ?? false)
    }

    /// Nothing today and every older range failing: no rows came, so it is the failed line.
    func testAFirstReadWithNoRowsBeforeAFailureIsTheFailedLine() async {
        let school = School(today: [])
        await school.set(failToday: false, failOlder: true)
        let loader = makeLoader(school)
        await loader.reload()
        XCTAssertEqual(loader.state.phase, .failed)
    }
}
