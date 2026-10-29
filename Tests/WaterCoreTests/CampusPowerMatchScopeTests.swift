import XCTest
@testable import WaterCore

final class CampusPowerMatchScopeTests: XCTestCase {
    private func config() throws -> CampusConfig {
        try JSONDecoder().decode(CampusConfig.self,from:Data(#"{"syscustid":"demo-owner","custid":"demo-card","acc_token":"demo-session","portal_dorm_address":"示例校区2栋3号5层504房","dorm_room":"示例校区 · 2栋 · 五楼 · 504"}"#.utf8))
    }
    func testSameResidenceSaveSurvivesPendingLookup() throws {
        let original = try config();var saved = original;saved.dormRoom = "2栋504"
        XCTAssertTrue(CampusPowerMatchScope(original).accepts(saved))
    }
    func testChangedAccountTokenResidenceAndManualMeterRejectOldResult() throws {
        let original = try config(), scope = CampusPowerMatchScope(original)
        var cases: [CampusConfig] = []
        var next = original;next.syscustid = "other";cases.append(next)
        next = original;next.custid = "other";cases.append(next)
        next = original;next.accToken = "new-session";cases.append(next)
        next = original;next.areacode = "other-campus-system";cases.append(next)
        next = original;next.portalDormAddress = "其他校区2栋3号5层504房";cases.append(next)
        next = original;next.dormRoom = "12栋504";cases.append(next)
        next = original;next.buildingID = "manual-building";cases.append(next)
        next = original;next.meterID = "manual-meter";cases.append(next)
        for changed in cases {XCTAssertFalse(scope.accepts(changed))}
    }
}
