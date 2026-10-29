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

    private func duplicateTree() -> [String:[CampusPowerBuilding]] {
        var tree: [String:[CampusPowerBuilding]] = ["root":[building("campus","示例校区")],
            "campus":[building("a","半山公寓"),building("b","兰香公寓")]]
        for group in ["a","b"] {
            tree[group] = [building(group+"-building","2栋")]
            tree[group+"-building"] = [building(group+"-floor","5楼")]
            tree[group+"-floor"] = [building(group+"-room","504")]
            tree[group+"-room"] = []
        }
        return tree
    }
    func testDuplicateFullPathsReturnApartmentChoicesWithoutReadingAnyBalances() async throws {
        let tree = duplicateTree()
        let result = try await CampusPowerResolver.resolve(address:address(),readBuildings:{tree[$0 ?? "root"] ?? []},
            readMeters:{_ in XCTFail("Ambiguous apartment must be chosen before reading meters"); return []})
        XCTAssertNil(result.suggestion)
        XCTAssertEqual(result.choices.map(\.label),["半山公寓 · 2栋 · 5楼 · 504","兰香公寓 · 2栋 · 5楼 · 504"])
        var calls: [String] = []
        let selected = try await CampusPowerResolver.select(try XCTUnwrap(result.choices.first),address:address(),readMeters:{parent in
            calls.append(parent)
            return [CampusElectricity(id:"own-meter",room:"504",remainingKWh:10,balanceYuan:5,yesterdayKWh:nil,meterUpdatedAt:"")]
        })
        XCTAssertEqual(calls,["a-room"]);XCTAssertEqual(selected?.meter.id,"own-meter")
    }
    func testFloorCanDisambiguateDuplicateBuildingNumbers() async throws {
        var tree = duplicateTree()
        tree["b-building"] = [building("b-wrong-floor","4楼")]
        let result = try await CampusPowerResolver.resolve(address:address(),readBuildings:{tree[$0 ?? "root"] ?? []},
            readMeters:{parent in XCTAssertEqual(parent,"a-room");return [self.meter("own-meter")]})
        XCTAssertEqual(result.suggestion?.meter.id,"own-meter");XCTAssertTrue(result.choices.isEmpty)
    }
    func testIncompleteOrCyclicCatalogueDoesNotClaimUniqueness() async throws {
        var tree = duplicateTree(); tree["b-room"] = [building("b","返回上层")]
        let result = try await CampusPowerResolver.resolve(address:address(),readBuildings:{tree[$0 ?? "root"] ?? []},
            readMeters:{_ in XCTFail("Partial discovery must not read a meter");return []})
        XCTAssertNil(result.suggestion);XCTAssertTrue(result.choices.isEmpty)
    }
    func testBareRoomMeterRequiresExactRoomPathAndMultipleMetersStayUnselected() async throws {
        var tree = duplicateTree();tree["campus"] = [building("a","公寓甲")]
        tree["a-floor"] = []
        let bare = CampusElectricity(id:"bare",room:"504",remainingKWh:10,balanceYuan:5,yesterdayKWh:nil,meterUpdatedAt:"")
        let unknown = try await CampusPowerResolver.resolve(address:address(),readBuildings:{tree[$0 ?? "root"] ?? []},readMeters:{_ in [bare]})
        XCTAssertNil(unknown.suggestion)
        tree["a-floor"] = [building("a-room","504")]
        let multiple = try await CampusPowerResolver.resolve(address:address(),readBuildings:{tree[$0 ?? "root"] ?? []},readMeters:{_ in [bare,self.meter("second")]})
        XCTAssertNil(multiple.suggestion)
    }
    func testFailedBranchCannotHideAnotherPossibleApartment() async throws {
        let tree = duplicateTree()
        do {
            _ = try await CampusPowerResolver.resolve(address:address(),readBuildings:{parent in
                if parent == "b" {throw CampusError.network};return tree[parent ?? "root"] ?? []
            },readMeters:{_ in XCTFail("Discovery failed");return []})
            XCTFail("Network failure must be visible and retryable")
        } catch {XCTAssertEqual(error as? CampusError,.network)}
    }
}
