//
//  OverlappingAccountSwitchTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
import Core
@testable import XiaoRiChang

/// Two account switches overlap: A → B's clean-up is held once the widget snapshot is cleared
/// (before the hot-water binding goes and B's dorm is written back) while B → C runs to its end,
/// C sets up hot water and reads their own balance. Released, A → B leaves C alone: C's snapshot,
/// dorm and binding stay, nothing of B shows, and its late end lets no new shower start.
/// Synthetic school, platform and controller; fake stores. Nothing real is read or sent.
@MainActor
final class OverlappingAccountSwitchTests: XCTestCase {
    typealias School = ShowerBalanceAccountTests.School

    static let dormB = "示例校区 1栋 101"
    static let dormC = "示例校区 2栋 202"
    static let bindingC = ShowerBinding(studentId:"S-3", schoolId:"1", machineId:"55667788", roomId:"R-3",
                                        roomLabel:"2栋 202", matchedAt:Date(timeIntervalSince1970:1_800_000_000))

    var school: School!
    var store: ScriptedStore!
    var http: CountingShowerHTTP!
    var link: ScriptedControllerLink!

    override func setUp() async throws {
        school = School(yuan:-0.5)
        store = ScriptedStore()
        http = CountingShowerHTTP()
        link = ScriptedControllerLink()
    }

    static func webLogin(card: String, dorm: String) -> CampusWebLogin {
        CampusWebLogin(state:Data(#"""
            {"logintoken":"SYNTHETIC-TOKEN","schoolid":"450010","loginInfo":{"syscustid":"SYNTHETIC-SYS","token":"SYNTHETIC-TOKEN"},"custInfo":{"custid":"SYNTHETIC-CUST","custunionid":"\#(card)"}}
            """#.utf8), dormAddress:dorm)
    }

    /// A signed in (card session stored), hot water set up with A's binding.
    func models() async throws -> (CampusModel, ShowerModel) {
        try StoredSchoolVault(store:store).saveEcyktSession(EcyktSession(token:"SYNTHETIC-A", syscustid:"SYNTHETIC-SYS",
                                                                         cardUnionID:"SYNTHETIC-CARD-A"))
        var binding = Fixture.binding
        binding.matchedAt = Date(timeIntervalSince1970:1_800_000_000)
        binding.peripheralID = "P"
        try StoredShowerVault(store:store).saveBinding(binding)
        let lease = LeaseFile(url:FileManager.default.temporaryDirectory.appendingPathComponent("overlap-lease-\(UUID().uuidString)"))
        let services = CampusServices(kind:.live, secureStore:store, defaults:SampleDefaults(), sharedPreferences:nil,
                                      schoolHTTP:school, showerHTTP:http, laundryHTTP:SampleHTTPClient(),
                                      feedbackHTTP:nil, showerTransport:link, leaseFile:lease,
                                      applicationSupport:try Fixture.supportWithProfile(), sharedDidChange:{})
        let reminders = Reminders.sample(defaults:services.defaults)
        let shower = ShowerModel(services:services, reminders:reminders, activities:nil, gate:LiveShowerGate(),
                                 bluetoothAccess:FakeBluetoothAccess())
        let campus = CampusModel(services:services, stack:services.schoolStack(), reminders:reminders) { shower }
        await shower.reloadProfile()
        await waitUntil { shower.gateRecord != .notLoaded && shower.engine != nil }
        XCTAssertTrue(campus.configured, "A is signed in")
        XCTAssertTrue(shower.mayStart, "A's hot water is ready")
        return (campus, shower)
    }

    func shortcutRefusal(_ shower: ShowerModel) async -> String? {
        do { _ = try await shower.startFromShortcut(clear:false); return nil }
        catch let failure as ShowerActionFailure { return failure.message }
        catch { return "\(error)" }
    }

    func settle(_ shower: ShowerModel) async {
        await pause(50)
        await waitUntil { !shower.busy && shower.startSlot == nil }
        await pause(20)
    }

    func testAnEarlierSwitchEndingLateLeavesTheLaterPersonAlone() async throws {
        let (campus, shower) = try await models()
        let held = ShowerBalanceAccountTests.Gate()
        var cleanUps = 0
        campus.afterSnapshotCleared = {
            cleanUps += 1
            if cleanUps == 1 { await held.wait() }
        }

        // A → B: its clean-up stops after the snapshot, before the binding and B's dorm.
        school.card = "SYNTHETIC-CARD-B"
        let aToB = Task { try await campus.adoptWebState(Self.webLogin(card:"SYNTHETIC-CARD-B", dorm:Self.dormB)) }
        await waitUntil { cleanUps == 1 }
        XCTAssertEqual(cleanUps, 1, "A → B's clean-up is held")

        // B → C runs to its end; C sets up hot water and reads −0.50.
        school.card = "SYNTHETIC-CARD-C"
        try await campus.adoptWebState(Self.webLogin(card:"SYNTHETIC-CARD-C", dorm:Self.dormC))
        XCTAssertEqual(cleanUps, 2, "B → C cleaned up")
        try shower.saveBinding(Self.bindingC)
        await campus.refresh(force:true)

        let snapshot = campus.snapshot
        XCTAssertEqual(snapshot.card.value, Money(fen:-50), "C's own read")
        let stored = try SharedSnapshotStore(store:store).loadSnapshot()
        XCTAssertEqual(stored?.card.value, Money(fen:-50))
        let profile = try StoredSchoolVault(store:store).profile()
        XCTAssertEqual(profile?.residence?.raw, Self.dormC)
        let notice = campus.switchNotice
        XCTAssertNotNil(notice)
        XCTAssertEqual(shower.balance?.amount, Money(fen:-50))

        // A → B ends now.
        held.open()
        _ = try? await aToB.value
        await settle(shower)

        XCTAssertEqual(try StoredSchoolVault(store:store).profile(), profile, "C's dorm is stored, not B's")
        XCTAssertEqual(campus.profile?.residence?.raw, Self.dormC)
        XCTAssertEqual(try StoredShowerVault(store:store).binding(), Self.bindingC, "C's binding stays")
        XCTAssertEqual(shower.binding, Self.bindingC)
        XCTAssertFalse(shower.residenceReviewRequired)
        XCTAssertEqual(try SharedSnapshotStore(store:store).loadSnapshot(), stored, "C's numbers stay")
        XCTAssertEqual(campus.snapshot, snapshot)
        XCTAssertEqual(campus.switchNotice, notice, "no notice of A → B over C's")
        XCTAssertTrue(campus.configured)

        // The late end lets nothing start: C's own −0.50 still refuses, and nothing is sent.
        XCTAssertEqual(shower.balance?.amount, Money(fen:-50), "C's balance stays")
        XCTAssertEqual(shower.startBlock, .balanceNegative)
        XCTAssertFalse(shower.mayStart)
        for entry in [ShowerStartIntent.Entry.page, .home] {
            let tap = shower.tapStart(entry)
            XCTAssertNotEqual(tap, .started(firstCheck:false), "\(entry)")
            XCTAssertNotEqual(tap, .started(firstCheck:true), "\(entry)")
        }
        let siri = await shortcutRefusal(shower)
        XCTAssertNotNil(siri, "Siri is refused")
        await settle(shower)
        XCTAssertEqual(http.sent, 0, "no authorize request")
        XCTAssertEqual(link.connects, 0, "no connect")
    }
}
