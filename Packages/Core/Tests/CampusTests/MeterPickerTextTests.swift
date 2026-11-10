import XCTest
import Core

/// The meter page opened where the lookup stopped: the matched levels on one line with 「重选」,
/// then this level's list under 「选…」, the row that may be the dorm's first.
final class MeterPickerTextTests: XCTestCase {
    static let address = DormAddress.parse("星湖校区99栋9号1层991房")!
    func nodes(_ names: String...) -> [PowerNode] { names.enumerated().map { PowerNode(id: "99\($0.offset)", name: $0.element) } }

    func testEachLevelNamesItsList() {
        XCTAssertEqual(MeterLevel.allCases.map(MeterPageText.header), ["选校区", "选公寓", "选楼栋", "选楼层", "选房间"])
        XCTAssertEqual(MeterPageText.suggestion, "可能是这个")
        XCTAssertEqual(MeterPageText.rechoose, "重选")
        XCTAssertEqual(MeterPageText.finding, "正在找电表…")
    }

    /// The levels already matched, floors left out as in every location.
    func testTheMatchedLevelsOnOneLine() {
        XCTAssertEqual(MeterPageText.matchedLine(nodes("星湖校区", "半山公寓", "99栋", "1楼")), "星湖校区 · 半山公寓 · 99栋")
        XCTAssertEqual(MeterPageText.matchedLine([]), "")
    }

    /// Suggested rows come first, in the order read; the others keep theirs.
    func testTheSuggestedRowsComeFirst() {
        let options = nodes("989", "990", "991", "992")
        let rows = MeterPageText.rows(options, suggested: ["992", "993"])
        XCTAssertEqual(rows.map(\.node.name), ["991", "992", "989", "990"])
        XCTAssertEqual(rows.map(\.suggested), [true, true, false, false])
        XCTAssertEqual(MeterPageText.rows(options, suggested: []).map(\.node), options)
        XCTAssertEqual(MeterPageText.rows(options, suggested: []).map(\.suggested), [false, false, false, false])
    }

    /// Below the stop, the user walks on by hand: each list's dorm row is offered first.
    /// Apartments are not named by the portal, so none is suggested there.
    func testTheDormsRowIsSuggestedAtEachLevel() {
        XCTAssertEqual(MeterPageText.suggested(nodes("星湖校区", "大旺校区"), at: .campus, for: Self.address), ["990"])
        XCTAssertEqual(MeterPageText.suggested(nodes("半山公寓", "樱花公寓"), at: .apartment, for: Self.address), [])
        XCTAssertEqual(MeterPageText.suggested(nodes("1栋", "99栋", "99 栋"), at: .building, for: Self.address), ["991", "992"])
        XCTAssertEqual(MeterPageText.suggested(nodes("1楼", "2楼"), at: .floor, for: Self.address), ["990"])
        XCTAssertEqual(MeterPageText.suggested(nodes("989", "991房"), at: .room, for: Self.address), ["991"])
        XCTAssertEqual(MeterPageText.suggested(nodes("星湖校区"), at: .campus, for: nil), [], "no dorm known")
    }

    /// What the next list is, from where the user was and what it holds.
    func testTheNextLevelIsToldFromItsRows() {
        XCTAssertEqual(MeterLevel.next(after: nil, options: nodes("星湖校区")), .campus)
        XCTAssertEqual(MeterLevel.next(after: .campus, options: nodes("半山公寓", "樱花公寓")), .apartment)
        XCTAssertEqual(MeterLevel.next(after: .campus, options: nodes("98栋", "99栋")), .building)
        XCTAssertEqual(MeterLevel.next(after: .apartment, options: nodes("1栋", "99幢", "3号楼")), .building)
        XCTAssertEqual(MeterLevel.next(after: .building, options: nodes("1楼", "2楼", "十二层")), .floor)
        XCTAssertEqual(MeterLevel.next(after: .building, options: nodes("101", "102")), .room, "rooms right under the building")
        XCTAssertEqual(MeterLevel.next(after: .floor, options: nodes("989", "990")), .room)
        XCTAssertEqual(MeterLevel.next(after: .room, options: nodes("A", "B")), .room)
    }

    /// The search field names what the list holds: buildings and rooms (the school's own names,
    /// e.g. 「99栋」, are shown as they are).
    func testTheSearchFieldAsksForABuildingOrRoom() {
        XCTAssertEqual(MeterPageText.searchPrompt, "搜索楼栋或房间")
    }

    /// Above a stopped level's list: only a failure is said; a lookup running again shows its
    /// spinner by the list header and nothing else.
    func testAboveAStoppedLevelOnlyAFailureIsSaid() {
        XCTAssertNil(MeterPageText.noteAtStop(finding: true, issue: nil), "no 「正在找电表…」 group")
        XCTAssertNil(MeterPageText.noteAtStop(finding: true, issue: ServiceError.timedOut.userMessage))
        XCTAssertNil(MeterPageText.noteAtStop(finding: false, issue: nil))
        XCTAssertNil(MeterPageText.noteAtStop(finding: false, issue: MeterPageText.stoppedIssue), "the list is the answer")
        XCTAssertEqual(MeterPageText.noteAtStop(finding: false, issue: ServiceError.timedOut.userMessage), "学校那边太慢了，等一下再找。")
        XCTAssertEqual(MeterPageText.noteAtStop(finding: false, issue: ServiceError.offline.userMessage), ServiceError.offline.userMessage)
        XCTAssertEqual(MeterPageText.stoppedIssue, "没自动找到电表，去「电表」里选一下。")
    }

    /// The lookup stopped with rooms in several apartments (or campuses): the question names how
    /// many, the dorm's building and room; nil when there is nothing to choose from.
    func testAStopWithCandidatesAsksWhichApartment() {
        let campus = PowerNode(id: "991001", name: "星湖校区")
        func candidate(_ apartment: PowerNode, _ room: String) -> MeterCandidate {
            MeterCandidate(meter: Meter(comAddress: "c" + room, name: "99栋991", leftMoney: nil),
                           path: [campus, apartment, PowerNode(id: apartment.id + "9", name: "99栋"), PowerNode(id: room, name: "991")])
        }
        let banshan = PowerNode(id: "991001001", name: "半山公寓"), lanxiang = PowerNode(id: "991001007", name: "兰香公寓")
        let stop = MeterWalkStop(level: .apartment, path: [campus], options: [banshan, lanxiang], suggested: [banshan.id, lanxiang.id],
                                 candidates: [candidate(banshan, "1"), candidate(lanxiang, "2")])
        XCTAssertEqual(MeterPageText.question(stop, address: Self.address), "2 个公寓都有 99 栋 991，你住哪个？")
        XCTAssertEqual(stop.candidates.map(stop.branchName), ["半山公寓", "兰香公寓"])
        let east = PowerNode(id: "992001", name: "东湖校区")
        let atCampus = MeterWalkStop(level: .campus, path: [], options: [campus, east], candidates: [
            candidate(banshan, "1"),
            MeterCandidate(meter: Meter(comAddress: "c3", name: "99栋991", leftMoney: nil),
                           path: [east, PowerNode(id: "9920019", name: "99栋"), PowerNode(id: "3", name: "991")]),
        ])
        XCTAssertEqual(MeterPageText.question(atCampus, address: Self.address), "2 个校区都有 99 栋 991，你住哪个？")
        XCTAssertEqual(atCampus.candidates.map(atCampus.branchName), ["星湖校区", "东湖校区"])
        XCTAssertNil(MeterPageText.question(MeterWalkStop(level: .apartment, path: [campus], options: [banshan]), address: Self.address))
        XCTAssertNil(MeterPageText.question(stop, address: nil))
    }

    /// Several apartments (or campuses) to tell apart and one could not be read.
    func testAnUnfinishedSplitSaysWhichLevel() {
        XCTAssertEqual(MeterPageText.unfinished(.apartment), "有个公寓没读完，还分不出是哪间。")
        XCTAssertEqual(MeterPageText.unfinished(.campus), "有个校区没读完，还分不出是哪间。")
    }
}
