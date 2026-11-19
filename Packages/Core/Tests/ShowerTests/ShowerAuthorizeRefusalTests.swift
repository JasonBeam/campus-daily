import XCTest
@testable import Core
import CoreTestSupport

/// Only an answer known to come before the platform acted is a definite "no" to an authorize:
/// `4002` (参数不匹配) and `-301` (sign rejected), both captured, plus a local refusal before
/// anything was sent. Any other non-zero code may come after an authorization was created,
/// so the record waits for a check.
final class ShowerAuthorizeRefusalTests: XCTestCase {
    let machine = "11223344"
    let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")
    var identity: Data { FakeFrames.identity(machine) }

    func authorizing() -> ShowerState {
        var s = ShowerReducer.reduce(.idle, .start(machineID: machine, preferredPeripheral: nil)).0
        s = ShowerReducer.reduce(s, .connected(peripheralID: "P", probe: identity)).0
        XCTAssertTrue(s.authorizeSent)
        return s
    }

    func testAnUnknownCodeIsNotADefiniteRefusal() {
        for code in ["1", "500", "-1", "9999"] {
            let e = ServiceError.rejected(.lxt6, code: code, message: "合成提示")
            let (s, fx) = ShowerReducer.reduce(authorizing(), .authorizeFailed(e))
            XCTAssertEqual(s.failure?.reason, .authorizeUncertain, code)
            XCTAssertEqual(s.failure?.needsReview, true, code)
            XCTAssertFalse(s.canStart, code)
            XCTAssertTrue(s.canResolveManually, code)
            XCTAssertEqual(s.persistable, s, "kept for the check (\(code))")
            XCTAssertEqual(fx, [.releaseDevice])
        }
    }

    func testTheKnownRequestRefusalsIssueNothing() async throws {
        for body in [#"{"code":4002,"message":"参数不匹配"}"#, #""{\"Code\":-301,\"Message\":\"sign\"}""#] {
            let server = StubServer()
            server.respond("POST", LxtEndpoints.base + "/" + LxtEndpoints.authorize, status: 200, body: Data(body.utf8))
            do {
                _ = try await Golden.client(server).authorize(Golden.binding, frame: Golden.frame)
                XCTFail("expected the refusal")
            } catch let e as ServiceError {
                let (s, _) = ShowerReducer.reduce(authorizing(), .authorizeFailed(e))
                XCTAssertEqual(s.failure?.reason, .authorizeRefused, body)
                XCTAssertEqual(s.failure?.needsReview, false, body)
                XCTAssertTrue(s.canStart)
            }
        }
        // No platform profile: refused here before anything leaves.
        let (local, _) = ShowerReducer.reduce(authorizing(), .authorizeFailed(.badRequest(.lxt6)))
        XCTAssertEqual(local.failure?.reason, .authorizeRefused)
    }

    func testAnUnknownCodeFromTheEngineBlocksTheNextStart() async throws {
        let vault = StoredShowerVault(store: InMemorySecureStore())
        let transport = FakeShowerTransport(), gateway = FakeGateway()
        let e = try ShowerEngine(transport: transport, gateway: gateway, vault: vault, configuration: .init(bleName: "fixture-ble"))
        transport.script(.frame(identity))
        gateway.scriptAuthorize(.fail(.rejected(.lxt6, code: "500", message: "合成提示")))
        let s = try await e.start(binding)
        XCTAssertEqual(s.failure?.reason, .authorizeUncertain)
        XCTAssertEqual(try vault.showerState()?.failure?.reason, .authorizeUncertain, "persisted")
        do { _ = try await e.start(binding); XCTFail("expected blocked") }
        catch let error as ShowerEngineError { XCTAssertEqual(error, .blocked) }
        XCTAssertEqual(gateway.authorizeFrames.count, 1)
    }
}
