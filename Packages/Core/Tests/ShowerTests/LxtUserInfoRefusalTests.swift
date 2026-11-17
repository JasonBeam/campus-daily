import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// `getUserMsg` only reads who the student is: a refusal code that still comes with the identity
/// (a low balance, say) does not stop the dorm from being bound. Without the identity it is the
/// refusal it was.
final class LxtUserInfoRefusalTests: XCTestCase {
    let url = "https://isv.lxt6.cn/AECC/GDBusinessSchool/getUserMsg"

    func reply(_ body: String) -> StubServer {
        let server = StubServer()
        server.respond("GET", url, headers: ["Content-Type": "text/html;charset=UTF-8"], body: Data(body.utf8))
        return server
    }

    func testARefusalThatStillCarriesTheIdentityIsAccepted() async throws {
        let server = reply(#"{"Code":1,"Message":"账户余额不足，请充值后使用","Data":{"schoolid":20021,"studentid":"991000000000000001"}}"#)
        let user = try await Golden.client(server).userInfo(Golden.handoff)
        XCTAssertEqual(user, ShowerUser(studentId: "991000000000000001", schoolId: "20021"))
    }

    func testARefusalAsAJSONStringWithTheIdentityIsAccepted() async throws {
        let inner = #"{\"code\":2,\"message\":\"欠费\",\"data\":{\"schoolid\":\"20021\",\"studentid\":\"S-99\"}}"#
        let server = reply("\"" + inner + "\"")
        let user = try await Golden.client(server).userInfo(Golden.handoff)
        XCTAssertEqual(user, ShowerUser(studentId: "S-99", schoolId: "20021"))
    }

    func testARefusalWithoutTheIdentityIsStillARefusal() async throws {
        let none = reply(#"{"Code":1,"Message":"账户余额不足，请充值后使用"}"#)
        await Golden.expectError(.rejected(.lxt6, code: "1", message: "账户余额不足，请充值后使用")) {
            _ = try await Golden.client(none).userInfo(Golden.handoff)
        }
        let partial = reply(#"{"Code":1,"Message":"账户余额不足","Data":{"schoolid":20021,"studentid":""}}"#)
        await Golden.expectError(.rejected(.lxt6, code: "1", message: "账户余额不足")) {
            _ = try await Golden.client(partial).userInfo(Golden.handoff)
        }
        let nullData = reply(#"{"Code":1,"Message":"账户余额不足","Data":null}"#)
        await Golden.expectError(.rejected(.lxt6, code: "1", message: "账户余额不足")) {
            _ = try await Golden.client(nullData).userInfo(Golden.handoff)
        }
    }

    func testOtherReadsStillStopAtARefusalCode() async throws {
        let server = StubServer()
        server.respond("GET", "https://isv.lxt6.cn/zk_areainfo_api/areaInfo/getAreaInfoForApplests",
                       body: Data(#"{"code":1,"msg":"余额不足","data":[{"id":"1","name":"校区"}]}"#.utf8))
        await Golden.expectError(.rejected(.lxt6, code: "1", message: "余额不足")) {
            _ = try await Golden.client(server).areas(parent: "20021")
        }
    }
}
