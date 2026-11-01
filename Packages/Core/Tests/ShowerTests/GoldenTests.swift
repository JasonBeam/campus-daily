import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// Signing + BLE codec goldens. Fixed inputs; expected values were produced by the previous
/// implementation (and an independent Python mirror of it) and are kept as hard-coded goldens.
enum Golden {
    static let secret = "fixture-secret ~/+"
    static let sid = "fixture-sid=1"
    static let frame = Data([0x55, 0x11, 0x22, 0x33, 0x44] + (0..<15).map { UInt8($0) })
    static let profile = ShowerPlatformProfile(secret: secret, sid: sid, bleName: "fixture-ble", typeId: "1", version: "3")
    static let binding = ShowerBinding(studentId: "S1234567", schoolId: "20021", machineId: "11223344", roomId: "R1", roomLabel: "99栋 991")

    static let operationWxcode = "studentId=S1234567*_schoolId=20021*_machineid=11223344*_machinedata=5511223344000102030405060708090A0B0C0D0E*_typeId=1*_alleywaytype=0*_rand=A1B2C3*_version=3"
    static let operationSign = "230d50952cd23127f1cd60a0f2c2b5ac"
    static let operationBody = "wxcode=studentId%3DS1234567*_schoolId%3D20021*_machineid%3D11223344*_machinedata%3D5511223344000102030405060708090A0B0C0D0E*_typeId%3D1*_alleywaytype%3D0*_rand%3DA1B2C3*_version%3D3&sign=230d50952cd23127f1cd60a0f2c2b5ac&sid=fixture-sid%3D1"
    static let areaQuery = "wxcode=id%3D20021&sign=946b706a2fd7f52e5087da07375c08b4&sid=fixture-sid%3D1"
    static let userMsgQuery = "wxcode=schoolid%3D20021*_vsuppid%3D9000001*_appid%3Dtest00appid0000001*_userId%3D90001*_deptId%3D0099*_username%3D%E6%B5%8B%E8%AF%95+%E5%91%98*_phone%3D13800000000*_random%3DABC123&sign=3a817931f5f12121bddc0ce27a31405f&sid=fixture-sid%3D1&requestType=1"

    /// Synthetic hand-off (same shape as `getSignData.appdata`, values as in the redacted fixture).
    static let handoff = ShowerHandoff(vsuppid: "9000001", appid: "test00appid0000001", userId: "90001", deptId: "0099",
                                      username: "测试 员", phone: "13800000000", sign: "x", nonce: "y", timestamp: "z")

    static func client(_ server: StubServer) -> LxtClient {
        LxtClient(http: server.makeClient(allowedHosts: AllowedHosts.hotWater), profile: profile,
                  random: { $0 == LxtSigning.userMsgAlphabet ? "ABC123" : "A1B2C3" })
    }

    static func expectError(_ expected: ServiceError, file: StaticString = #filePath, line: UInt = #line,
                            _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let e as ServiceError {
            XCTAssertEqual(e, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}

final class LxtSigningGoldenTests: XCTestCase {
    func testFormEncodingMatchesMiniProgram() {
        XCTAssertEqual(LxtSigning.formEncode("a b+~!'()*_-.中文"), "a+b%2B%7E%21%27%28%29*_-.%E4%B8%AD%E6%96%87")
        XCTAssertEqual(LxtSigning.signature(secret: "", wxcode: ""), "d41d8cd98f00b204e9800998ecf8427e")
    }

    func testOperationWxcodeAndSignatureGolden() {
        let fields = LxtSigning.operationFields(studentId: "S1234567", schoolId: "20021", machineId: "11223344", frame: Golden.frame,
                                                typeId: "1", version: "3", random: "A1B2C3")
        let code = LxtSigning.wxcode(fields)
        XCTAssertEqual(code, Golden.operationWxcode)
        XCTAssertEqual(LxtSigning.signature(secret: Golden.secret, wxcode: code), Golden.operationSign)
        XCTAssertEqual(LxtSigning.signedForm(fields, secret: Golden.secret, sid: Golden.sid), Golden.operationBody)
    }

    func testFormEncodingGoldens() {
        XCTAssertEqual(LxtSigning.formEncode("a=b*_c"), "a%3Db*_c")
        XCTAssertEqual(LxtSigning.formEncode(" "), "+")
    }

    func testAuthorizePostBodyIsTheGoldenForm() async throws {
        let server = StubServer()
        server.respond("POST", "https://isv.lxt6.cn/ZK_BSRS/GDBusinessSchool/bathingConsumptionAuthorization",
                       body: Data(#"{"code":0,"data":{"machineid":"11223344","studentId":"001122FF","systemData":"000102030405060708090A0B0C0D0E"}}"#.utf8))
        _ = try await Golden.client(server).authorize(Golden.binding, frame: Golden.frame)
        let req = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(String(decoding: req.body, as: UTF8.self), Golden.operationBody)
        XCTAssertEqual(req.header("Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertNil(req.url.query)
    }

    func testReadQueriesAreTheGoldenSignedQuery() async throws {
        let server = StubServer()
        try server.serve("lxt6/areaInfo-level0")
        try server.serve("lxt6/getUserMsg-ok")
        let client = Golden.client(server)
        _ = try await client.areas(parent: "20021")
        _ = try await client.userInfo(Golden.handoff)
        XCTAssertEqual(server.requests.map { $0.url.query }, [Golden.areaQuery, Golden.userMsgQuery])
        XCTAssertEqual(server.requests.map(\.method), ["GET", "GET"])
    }
}

final class ShowerFrameGoldenTests: XCTestCase {
    func testCloseCommandGolden() throws {
        XCTAssertEqual(ShowerFrames.closeCommand(authorizationID: "001122FF"), Data([0xAC, 0x55, 0x44, 0x77, 0xAA]))
        XCTAssertEqual(ShowerFrames.closeCommand(authorizationID: "a1b2c3d4"), Data([0xAC, 0xF4, 0xE7, 0x96, 0x81]))
        XCTAssertEqual(ShowerFrames.closeCommand(authorizationID: "FFFFFFFF"), Data([0xAC, 0xAA, 0xAA, 0xAA, 0xAA]))
        XCTAssertEqual(ShowerFrames.closeCommand(authorizationID: "00000000"), Data([0xAC, 0x55, 0x55, 0x55, 0x55]))
        for bad in ["", "0011", "001122FG", "001122FF00", " 001122F"] {
            XCTAssertNil(ShowerFrames.closeCommand(authorizationID: bad), bad)
        }
    }

    func testIdentityGolden() throws {
        XCTAssertEqual(ShowerFrames.identity(Golden.frame), "11223344")
        XCTAssertNil(ShowerFrames.identity(Data(Golden.frame.prefix(19))))
        XCTAssertNil(ShowerFrames.identity(Data([0x56]) + Golden.frame.dropFirst()))
        XCTAssertEqual(ShowerFrames.classify(Data([0xA5])), .active)
        XCTAssertEqual(ShowerFrames.classify(Golden.frame), .idle(machineID: "11223344"))
        XCTAssertEqual(ShowerFrames.classify(Data([0xAA])), .unreadable)
        XCTAssertTrue(ShowerFrames.isAck(Data([0xAA] + [UInt8](repeating: 0, count: 8))))
        XCTAssertFalse(ShowerFrames.isAck(Data([0xAA] + [UInt8](repeating: 0, count: 7))))
        XCTAssertEqual(ShowerFrames.command(ShowerFrames.probeCommand), .probe)
        XCTAssertEqual(ShowerFrames.command(Data(count: 15)), .authorization)
        XCTAssertEqual(ShowerFrames.command(Data([0xAC, 0, 0, 0, 0])), .close)
        XCTAssertEqual(ShowerFrames.serviceUUID + ShowerFrames.notifyUUID + ShowerFrames.writeUUID, "FFE0FFE1FFE2")
    }

    func testAssemblerOnFixedChunkings() throws {
        let ack = Data([0xAA] + [UInt8](repeating: 7, count: 8))
        let stream = Golden.frame + ack + Data([0xA5]) + Golden.frame
        for split in [[7], [1, 1, 1], [20, 9, 1], [3, 25], [40], [stream.count]] {
            var mine = ShowerFrameAssembler()
            var a: [Data] = []
            var offset = 0, i = 0
            while offset < stream.count {
                let n = min(split[i % split.count], stream.count - offset)
                let chunk = Data(stream[stream.startIndex + offset ..< stream.startIndex + offset + n])
                a += try mine.append(chunk)
                offset += n; i += 1
            }
            XCTAssertEqual(a, [Golden.frame, ack, Data([0xA5]), Golden.frame])
            XCTAssertFalse(mine.hasPartialFrame)
        }
    }

    func testAssemblerRejectsUnknownBytesAndOverflow() {
        var a = ShowerFrameAssembler()
        XCTAssertThrowsError(try a.append(Data([0x00])))
        var b = ShowerFrameAssembler()
        XCTAssertNoThrow(try b.append(Data([0x55, 1, 2])))
        XCTAssertTrue(b.hasPartialFrame)
        var c = ShowerFrameAssembler()
        XCTAssertThrowsError(try c.append(Data([0x55]) + Data(count: 300)))
    }

    func testHexStrictness() {
        XCTAssertNil(HexCoding.data("00 ZZ"))
        XCTAssertNil(HexCoding.data("1"))
        XCTAssertEqual(HexCoding.data("aaFF"), Data([0xAA, 0xFF]))
        XCTAssertEqual(HexCoding.upper(Data([0x0A, 0xFF])), "0AFF")
    }

    func testReceiptParsing() {
        XCTAssertEqual(ShowerReceipt.parse(pay: .int(9)).amount, Money(fen: 9))
        XCTAssertEqual(ShowerReceipt.parse(pay: .string("163")).amount?.yuanText, "1.63")
        XCTAssertEqual(ShowerReceipt.parse(pay: .int(0)).amount, Money.zero)
        for bad: JSONValue? in [nil, .bool(true), .int(-1), .string(""), .string("9abc"), .null, .double(0.5), .int(100_000_000_001)] {
            XCTAssertNil(ShowerReceipt.parse(pay: bad).amount, "\(String(describing: bad))")
        }
    }
}
