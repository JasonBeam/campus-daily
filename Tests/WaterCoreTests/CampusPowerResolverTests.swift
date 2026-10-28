import XCTest
@testable import WaterCore

@MainActor final class CampusPowerResolverTests: XCTestCase {
    private func address() throws -> PortalDormAddress {try XCTUnwrap(PortalDormAddress.parse("示例校区2栋3号5层504房"))}
    private func building(_ id: String,_ name: String) -> CampusPowerBuilding {CampusPowerBuilding(id:id,name:name)}
    private func meter(_ id: String) -> CampusElectricity {CampusElectricity(id:id,room:"2栋504",remainingKWh:10,balanceYuan:5,yesterdayKWh:nil,meterUpdatedAt:"")}
    func testFullIndependentHierarchyFindsOnlyOwnRoomAndReturnsServerIDs() async throws {
        let tree: [String:[CampusPowerBuilding]] = [
            "root":[building("campus-a","示例校区"),building("other-campus","别的校区")],
            "campus-a":[building("residence-group","半山公寓")],
            "residence-group":[building("building-a","2栋"),building("building-b","3栋")],
            "building-a":[building("floor-a","5楼"),building("floor-b","6楼")],
            "floor-a":(501...519).map{building("room-\($0)",String($0))},"room-504":[]]
        var requests: [String] = [], meterRequests: [String] = []
        let result = try await CampusPowerResolver.suggest(address:address(),readBuildings:{parent in
            let key=parent ?? "root";requests.append(key);return tree[key] ?? []
        },readMeters:{parent in meterRequests.append(parent);return [self.meter("server-meter-id")]})
        XCTAssertEqual(result?.building,"room-504");XCTAssertEqual(result?.meter.id,"server-meter-id")
        XCTAssertEqual(meterRequests,["room-504"])
        XCTAssertFalse(requests.contains("other-campus"));XCTAssertFalse(requests.contains("room-503"));XCTAssertFalse(requests.contains("building-b"))
    }
    func testTwoDifferentResidenceGroupsWithSameRoomRemainAmbiguous() async throws {
        let result = try await CampusPowerResolver.suggest(address:address(),readBuildings:{parent in
            switch parent {
            case nil:return [self.building("campus","示例校区")]
            case "campus":return [self.building("group-a","公寓甲"),self.building("group-b","公寓乙")]
            default:return []
            }
        },readMeters:{parent in [self.meter("meter-"+parent)]})
        XCTAssertNil(result)
    }
    func testTruncatedSearchCannotClaimUniqueMatch() async throws {
        let result = try await CampusPowerResolver.suggest(address:address(),readBuildings:{parent in
            if parent == nil {return [self.building("campus","示例校区")]}
            return [self.building((parent ?? "")+"/next","分组")]
        },readMeters:{_ in XCTFail("No known leaf was reached");return []})
        XCTAssertNil(result)
    }
}
