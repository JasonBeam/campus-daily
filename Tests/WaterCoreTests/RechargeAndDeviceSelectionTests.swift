import XCTest
@testable import WaterCore

final class CampusWebSessionTests: XCTestCase {
    private func config() throws -> CampusConfig {
        try JSONDecoder().decode(CampusConfig.self,from:Data(#"{"syscustid":"student-test","acc_token":"test-token","areacode":"test-school","custid":"card-test","timestamp":"123"}"#.utf8))
    }
    func testVerifiedSessionCarriesFullOfficialCardContext() throws {
        let value = try CampusWebSession.create(config:config(),login:["syscustid":"student-test","isbind":1],cards:[["custid":"card-test","displayName":"测试卡"]])
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with:value.state) as? [String:Any])
        XCTAssertEqual(state["logintoken"] as? String,"test-token")
        XCTAssertEqual((state["loginInfo"] as? [String:Any])?["timestamp"] as? String,"123")
        XCTAssertEqual((state["custInfo"] as? [String:Any])?["displayName"] as? String,"测试卡")
    }
    func testOfficialBridgeRotatedIdentifiersUseAuthenticatedSingleCard() throws {
        let value = try CampusWebSession.create(config:config(),login:["syscustid":"rotated-owner","isbind":1],cards:[["custid":"rotated-card"]])
        XCTAssertEqual(value.syscustid,"rotated-owner")
        XCTAssertEqual(value.custid,"rotated-card")
    }
    func testUnboundOrMissingOwnerIsRejected() throws {
        for login: [String:Any] in [["syscustid":"owner","isbind":0],["isbind":1]] {
            XCTAssertThrowsError(try CampusWebSession.create(config:config(),login:login,cards:[["custid":"card-test"]]))
        }
    }
    func testAnotherCardOwnerIsRejected() throws {
        XCTAssertThrowsError(try CampusWebSession.create(config:config(),login:["syscustid":"student-test","isbind":1],cards:[["custid":"card-test","syscustid":"another"]])) {
            XCTAssertEqual($0 as? CampusError,.expired)
        }
    }
    func testConfiguredCardIsSelectedInsteadOfFirstReturnedCard() throws {
        let value = try CampusWebSession.create(config:config(),login:["syscustid":"student-test","isbind":1],cards:[["custid":"other-card"],["custid":"card-test"]])
        XCTAssertEqual(value.custid,"card-test")
    }
    func testMissingOrDuplicateConfiguredCardCannotFallBack() throws {
        for cards in [[["custid":"other-card"],["custid":"second-card"]],[["custid":"card-test"],["custid":"card-test"]]] {
            XCTAssertThrowsError(try CampusWebSession.create(config:config(),login:["syscustid":"student-test","isbind":1],cards:cards)) {
                XCTAssertEqual($0 as? CampusError,.ambiguous)
            }
        }
    }
    func testRechargeURLsDoNotExposeTokenOrUseMiniAuth() throws {
        let value = try CampusWebSession.create(config:config(),login:["syscustid":"student-test","isbind":1],cards:[["custid":"card-test"]])
        XCTAssertEqual(value.rechargeURL(power:false).path,"/ykt-view/recharge")
        for power in [false,true] {
            let url = value.rechargeURL(power:power)
            XCTAssertEqual(url.host,"ecykt.gdbtu.edu.cn")
            XCTAssertFalse(url.absoluteString.contains("test-token"))
            XCTAssertFalse(url.absoluteString.contains("AuthMini"))
        }
        let query = URLComponents(url:value.rechargeURL(power:true),resolvingAgainstBaseURL:false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "custid" }?.value,"card-test")
    }
    func testBootstrapIsOriginScopedAndDoesNotContainPasswordCode() throws {
        let value = try CampusWebSession.create(config:config(),login:["syscustid":"student-test","isbind":1],cards:[["custid":"card-test"]])
        XCTAssertTrue(value.bootstrapScript.contains("location.hostname!==\"ecykt.gdbtu.edu.cn\""))
        XCTAssertTrue(value.bootstrapScript.contains("elecampus_state"))
        XCTAssertFalse(value.bootstrapScript.contains("password"))
        XCTAssertFalse(value.bootstrapScript.contains("fetch("))
    }
}

@MainActor final class WaterIdentitySelectionTests: XCTestCase {
    private func identity(_ hex: String) -> Data { Data([0x55]) + Data(strictHex:hex)! + Data(repeating:0,count:15) }
    func testSkipsOtherDormEvenWhenItIsFirst() async throws {
        var calls: [String] = []
        let selected = try await WaterIdentitySelection.match(["strong-neighbor","own-dorm"],machineID:"01020304") { id in
            calls.append(id); return self.identity(id == "own-dorm" ? "01020304" : "05060708")
        }
        XCTAssertEqual(selected,"own-dorm")
        XCTAssertEqual(calls,["strong-neighbor","own-dorm"])
    }
    func testStopsOnceExactDormIdentityIsFound() async throws {
        var calls = 0
        let selected = try await WaterIdentitySelection.match(["own-dorm","neighbor"],machineID:"01020304") { _ in calls += 1; return self.identity("01020304") }
        XCTAssertEqual(selected,"own-dorm"); XCTAssertEqual(calls,1)
    }
    func testBusyAndMalformedFramesDoNotIdentifyDevice() async {
        do {
            _ = try await WaterIdentitySelection.match(["busy","bad"],machineID:"01020304") { id in id == "busy" ? Data([0xA5]) : Data([0x55]) }
            XCTFail("Busy or malformed frames cannot prove ownership")
        } catch { XCTAssertEqual(error as? WaterError,.targetMissing) }
    }
    func testAllOtherIdentitiesFailWithoutChoosingAny() async {
        do {
            _ = try await WaterIdentitySelection.match(["other"],machineID:"01020304") { _ in self.identity("05060708") }
            XCTFail("Must not choose another dorm")
        } catch { XCTAssertEqual(error as? WaterError,.wrongDevice) }
    }
    func testUnreachableCandidateDoesNotHideExactMatch() async throws {
        let selected = try await WaterIdentitySelection.match(["offline","own"],machineID:"01020304") { id in
            if id == "offline" { throw WaterError.timedOut }
            return self.identity("01020304")
        }
        XCTAssertEqual(selected,"own")
    }
    func testCancellationDoesNotProbeAnotherDevice() async {
        var calls = 0
        do {
            _ = try await WaterIdentitySelection.match(["a","b"],machineID:"01020304") { _ in calls += 1; throw CancellationError() }
            XCTFail("Must propagate cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(calls,1)
    }
}
