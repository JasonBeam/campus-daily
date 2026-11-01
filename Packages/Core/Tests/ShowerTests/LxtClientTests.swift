import XCTest
import Foundation
@testable import Core
import CoreTestSupport

final class LxtClientTests: XCTestCase {
    let base = "https://isv.lxt6.cn/"
    var frame: Data { Golden.frame }

    func operationReply(_ server: StubServer, _ path: String, status: Int = 200, _ body: String) {
        server.respond("POST", base + path, status: status, body: Data(body.utf8))
    }

    // MARK: Reads

    func testUserInfoReadsIdentityFromCapitalisedEnvelope() async throws {
        let server = StubServer()
        try server.serve("lxt6/getUserMsg-ok")
        let user = try await Golden.client(server).userInfo(Golden.handoff)
        XCTAssertEqual(user, ShowerUser(studentId: "991000000000000001", schoolId: "20021"))
        XCTAssertEqual(server.requests.first?.queryItem("requestType"), "1")
        XCTAssertFalse(user.description.contains("1795606"))
    }

    func testUserInfoBadSignIsBadRequestAndMissingHandoffFieldNeverSent() async throws {
        let server = StubServer()
        try server.serve("lxt6/getUserMsg-badSign")
        await Golden.expectError(.badRequest(.lxt6)) { _ = try await Golden.client(server).userInfo(Golden.handoff) }

        var noPhone = Golden.handoff
        noPhone.phone = ""
        let before = server.requests.count
        await Golden.expectError(.malformed(.ecykt, "appdata.phone")) { _ = try await Golden.client(server).userInfo(noPhone) }
        XCTAssertEqual(server.requests.count, before)
    }

    func testAreaReadsAndEnvelopeCodes() async throws {
        let server = StubServer()
        try server.serve("lxt6/areaInfo-level0", times: 1)
        let client = Golden.client(server)
        let campuses = try await client.areas(parent: "20021")
        XCTAssertEqual(campuses.count, 6)
        XCTAssertEqual(campuses[1], AreaNode(id: "997000000000014501", name: "星湖校区"))

        try server.serve("lxt6/areaInfo-badSign", times: 1)
        await Golden.expectError(.badRequest(.lxt6)) { _ = try await client.areas(parent: "20021") }
        try server.serve("lxt6/areaInfo-missingId", times: 1)
        await Golden.expectError(.badRequest(.lxt6)) { _ = try await client.areas(parent: "") }
        try server.serve("lxt6/areaInfo-unknownParent", times: 1)
        await Golden.expectError(.rejected(.lxt6, code: "4034", message: "查无此信息，请联系管理员完善地址信息！")) {
            _ = try await client.areas(parent: "999999999999999999")
        }
        server.respond("GET", base + LxtEndpoints.areaInfo, status: 502, body: Data("bad gateway".utf8), times: 1)
        await Golden.expectError(.rejected(.lxt6, code: "HTTP 502", message: "")) { _ = try await client.areas(parent: "1") }
        server.respond("GET", base + LxtEndpoints.areaInfo, body: Data(#"{"code":0,"data":[{"id":"1","name":"a"},{"id":"1","name":"b"}]}"#.utf8), times: 1)
        await Golden.expectError(.malformed(.lxt6, "data.id")) { _ = try await client.areas(parent: "1") }
        server.respond("GET", base + LxtEndpoints.areaInfo, body: Data(#"{"code":0,"data":[{"id":"","name":"a"}]}"#.utf8), times: 1)
        await Golden.expectError(.malformed(.lxt6, "data[0].id")) { _ = try await client.areas(parent: "1") }
        XCTAssertTrue(server.unmatched.isEmpty)
    }

    func testMachinesDecodeAndUnknownRoom() async throws {
        let server = StubServer()
        try server.serve("lxt6/getMachineMacAddress-ok", times: 1)
        let client = Golden.client(server)
        let machines = try await client.machines(room: "991000000000000002", schoolId: "20021")
        XCTAssertEqual(machines, [ShowerMachine(machineId: "1A2B3C4D", name: "9-901", mac: "02:00:00:00:00:01")])
        XCTAssertEqual(server.requests.last?.queryItem("wxcode"), "typeId=1*_schoolId=20021*_roomId=991000000000000002")

        try server.serve("lxt6/getMachineMacAddress-unknownRoom", times: 1)
        await Golden.expectError(.rejected(.lxt6, code: "5000", message: "系统提示： 当前房间未绑定设备")) {
            _ = try await client.machines(room: "999999999999999999", schoolId: "20021")
        }
        server.respond("GET", base + LxtEndpoints.machines, body: Data(#"{"code":0,"data":{"objList":[{"machineId":"XYZ","machineName":"a","Mac":"m"}]}}"#.utf8), times: 1)
        await Golden.expectError(.malformed(.lxt6, "data.objList[0].machineId")) { _ = try await client.machines(room: "1", schoolId: "20021") }
    }

    // MARK: Authorize / settle

    func testAuthorizeDecodesG1Reply() async throws {
        let server = StubServer()
        operationReply(server, LxtEndpoints.authorize, #"{"code":0,"data":{"machineid":"11223344","studentId":"a1b2c3d4","systemData":"000102030405060708090a0b0c0d0e"}}"#)
        let a = try await Golden.client(server).authorize(Golden.binding, frame: frame)
        XCTAssertEqual(a, ShowerAuthorization(machineID: "11223344", payload: Data((0..<15).map { UInt8($0) }), authorizationID: "A1B2C3D4"))
        XCTAssertFalse(a.description.contains("A1B2C3D4"))
    }

    func testAuthorizeOutcomes() async throws {
        let cases: [(Int, String, ServiceError)] = [
            (200, #"{"code":1,"message":"余额不足"}"#, .rejected(.lxt6, code: "1", message: "余额不足")),
            (200, #"{"code":4002,"message":"参数不匹配"}"#, .badRequest(.lxt6)),
            (200, #""{\"Code\":-301,\"Message\":\"sign\"}""#, .badRequest(.lxt6)),
            (500, #"{"code":0,"data":{}}"#, .uncertain(.lxt6)),
            (200, "<html>", .uncertain(.lxt6)),
            (200, #"{"message":"OK"}"#, .uncertain(.lxt6)),
            (200, #"{"code":0,"data":null}"#, .uncertain(.lxt6)),
            (200, #"{"code":0,"data":{"machineid":"11223344","studentId":"001122FF","systemData":"0001"}}"#, .uncertain(.lxt6)),
            (200, #"{"code":0,"data":{"machineid":"11223344","studentId":"0011","systemData":"000102030405060708090A0B0C0D0E"}}"#, .uncertain(.lxt6)),
        ]
        for (status, body, expected) in cases {
            let server = StubServer()
            operationReply(server, LxtEndpoints.authorize, status: status, body)
            await Golden.expectError(expected) { _ = try await Golden.client(server).authorize(Golden.binding, frame: self.frame) }
            XCTAssertEqual(server.requests.count, 1, "never retried: \(body)")
        }
    }

    func testOperationsRefuseAFrameFromAnotherControllerBeforeSending() async throws {
        let server = StubServer()
        let other = FakeFrames.identity("99999999")
        await Golden.expectError(.badRequest(.lxt6)) { _ = try await Golden.client(server).authorize(Golden.binding, frame: other) }
        await Golden.expectError(.badRequest(.lxt6)) { _ = try await Golden.client(server).settle(Golden.binding, frame: Data([0xA5])) }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testOperationTransportFailureIsNotARefusal() async throws {
        let server = StubServer()
        server.fail("POST", base + LxtEndpoints.settle, with: .timedOut)
        do {
            _ = try await Golden.client(server).settle(Golden.binding, frame: frame)
            XCTFail("expected failure")
        } catch let e as ServiceError {
            XCTAssertFalse(ShowerReducer.isDefiniteRefusal(e), "\(e)")
        }
        XCTAssertEqual(server.requests.count, 1)
    }

    func testSettleDecodesPayFen() async throws {
        for (body, fen) in [(#"{"code":0,"data":{"pay":163}}"#, Optional(163)), (#"{"code":0,"data":{"pay":"0"}}"#, 0),
                            (#"{"code":0,"data":{"pay":1.5}}"#, nil), (#"{"code":0,"data":{}}"#, nil)] {
            let server = StubServer()
            operationReply(server, LxtEndpoints.settle, body)
            let r = try await Golden.client(server).settle(Golden.binding, frame: frame)
            XCTAssertEqual(r.amount, fen.map { Money(fen: $0) }, body)
            XCTAssertEqual(server.requests.first?.formFields["wxcode"]?.contains("machinedata=5511223344"), true)
        }
        let server = StubServer()
        operationReply(server, LxtEndpoints.settle, #"{"code":3,"message":"重复结算"}"#)
        await Golden.expectError(.rejected(.lxt6, code: "3", message: "重复结算")) { _ = try await Golden.client(server).settle(Golden.binding, frame: self.frame) }
    }
}

// MARK: - Onboarding

/// Directory double for cases the fixtures do not cover.
struct FakeDirectory: ShowerDirectory {
    var tree: [String: [AreaNode]]
    var machineRows: [String: [ShowerMachine]] = [:]
    var error: ServiceError?
    func areas(parent: String) async throws -> [AreaNode] {
        if let error { throw error }
        return tree[parent] ?? []
    }
    func rooms(floor: String) async throws -> [AreaNode] { try await areas(parent: floor) }
    func machines(room: String, schoolId: String) async throws -> [ShowerMachine] { machineRows[room] ?? [] }
}

final class ShowerOnboardingTests: XCTestCase {
    let address = DormAddress.parse("星湖校区99栋9号1层991房")!

    func fixtureServer() throws -> StubServer {
        let server = StubServer()
        for name in ["areaInfo-level0", "areaInfo-level1", "areaInfo-level2", "areaInfo-level3",
                     "getMachineMacAddress-ok", "getMachineMacAddress-unknownRoom", "areaInfo-unknownParent"] {
            server.serve(try FixtureLoader.load("lxt6/" + name), matchQuery: ["wxcode"])
        }
        return server
    }

    func testEndToEndFromPortalAddressToController() async throws {
        let server = try fixtureServer()
        let onboarding = ShowerOnboarding(directory: Golden.client(server))
        let result = try await onboarding.match(address, schoolId: "20021")
        let path = [AreaNode(id: "997000000000014501", name: "星湖校区"), AreaNode(id: "997000000000090009", name: "99栋"),
                    AreaNode(id: "997000000000090101", name: "一楼"), AreaNode(id: "991000000000000002", name: "991")]
        XCTAssertEqual(result, .matched(path: path, machine: ShowerMachine(machineId: "1A2B3C4D", name: "9-901", mac: "02:00:00:00:00:01")))
        XCTAssertEqual(ShowerOnboarding.roomLabel(path), "99栋 991")
        XCTAssertTrue(ShowerOnboarding.pathMatches(path, address: address))
        XCTAssertTrue(server.unmatched.isEmpty)
        XCTAssertEqual(server.requests.map { $0.url.lastPathComponent },
                       ["getAreaInfoForApplests", "getAreaInfoForApplests", "getAreaInfoForApplests", "getAreaForRoomApplests", "getMachineMacAddress"])
    }

    func testUnmatchedLevelHandsOptionsToThePicker() async throws {
        let server = try fixtureServer()
        let onboarding = ShowerOnboarding(directory: Golden.client(server))
        let room200 = DormAddress.parse("星湖校区99栋9号1层200房")!
        guard case .pick(let level, let options, let path) = try await onboarding.match(room200, schoolId: "20021") else {
            return XCTFail("expected pick")
        }
        XCTAssertEqual(level, .room)
        XCTAssertEqual(options.map(\.name), ["989", "990", "991"])
        XCTAssertEqual(path.map(\.name), ["星湖校区", "99栋", "一楼"])

        let otherCampus = DormAddress.parse("示例校区99栋1层991房")!
        guard case .pick(.campus, let campuses, let none) = try await onboarding.match(otherCampus, schoolId: "20021") else {
            return XCTFail("expected campus pick")
        }
        XCTAssertEqual(campuses.count, 6)
        XCTAssertTrue(none.isEmpty)
    }

    func testRoomWithoutControllerAndUnknownAddress() async throws {
        let server = try fixtureServer()
        let onboarding = ShowerOnboarding(directory: Golden.client(server))
        let path = [AreaNode(id: "999999999999999999", name: "991")]
        do { let r = try await onboarding.controllers(path: path, schoolId: "20021"); XCTAssertEqual(r, .noController(path: path, message: "这个房间没有水控")) }
        do { let r = try await onboarding.match(address, schoolId: "999999999999999999"); XCTAssertEqual(r, .addressUnknown(message: "查无此信息，请联系管理员完善地址信息！")) }
    }

    func testAmbiguityIsNeverResolvedByGuessing() async throws {
        let tree: [String: [AreaNode]] = [
            "S": [AreaNode(id: "c", name: "星湖校区")],
            "c": [AreaNode(id: "b1", name: "99栋"), AreaNode(id: "b2", name: "99幢")],
        ]
        let onboarding = ShowerOnboarding(directory: FakeDirectory(tree: tree))
        let r = try await onboarding.match(address, schoolId: "S")
        XCTAssertEqual(r, .pick(level: .building, options: tree["c"]!, path: [AreaNode(id: "c", name: "星湖校区")]))

        let path = [AreaNode(id: "c", name: "星湖校区"), AreaNode(id: "b", name: "99栋"), AreaNode(id: "f", name: "1层"), AreaNode(id: "r", name: "991房")]
        let two = [ShowerMachine(machineId: "00000001", name: "a", mac: ""), ShowerMachine(machineId: "00000002", name: "b", mac: "")]
        let many = ShowerOnboarding(directory: FakeDirectory(tree: [:], machineRows: ["r": two]))
        do { let r = try await many.controllers(path: path, schoolId: "S"); XCTAssertEqual(r, .chooseMachine(path: path, machines: two)) }
        let none = ShowerOnboarding(directory: FakeDirectory(tree: [:]))
        do { let r = try await none.controllers(path: path, schoolId: "S"); XCTAssertEqual(r, .noController(path: path, message: ShowerOnboarding.noControllerText)) }
        XCTAssertTrue(ShowerOnboarding.pathMatches(path, address: address))
        XCTAssertFalse(ShowerOnboarding.pathMatches(Array(path.reversed()), address: address))
    }

    func testOtherErrorsPropagate() async throws {
        let onboarding = ShowerOnboarding(directory: FakeDirectory(tree: [:], error: .offline))
        await Golden.expectError(.offline) { _ = try await onboarding.match(self.address, schoolId: "S") }
    }
}
