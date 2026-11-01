import XCTest
import Core

final class ShowerProfileSourceTests: XCTestCase {
    struct Provider: ShowerProfileProviding {
        func resolve(_ source: ShowerProfileSource) async throws -> ShowerPlatformAccess {
            switch source {
            case .bundled: throw ShowerProfileError.missing(.bundled)
            case .imported(let name):
                return .local(try ShowerProfileResolver.decodeProfile(Data(#"{"secret":"s","sid":"i","ble_name":"b","type_id":1,"version":2,"student_id":"x"}"#.utf8), source: .imported(fileName: name)), source: source)
            }
        }
    }

    func testDecodeAcceptsBothKeyStylesAndRejectsIncomplete() throws {
        let p = try ShowerProfileResolver.decodeProfile(Data(#"{"secret":"s","sid":"i","bleName":"b","typeId":"1","version":"2"}"#.utf8), source: .bundled)
        XCTAssertEqual(p.typeId, "1")
        XCTAssertFalse(p.description.contains("s,"))
        XCTAssertFalse("\(p)".contains("\"s\""))
        XCTAssertThrowsError(try ShowerProfileResolver.decodeProfile(Data(#"{"secret":"","sid":"i"}"#.utf8), source: .bundled)) {
            XCTAssertEqual($0 as? ShowerProfileError, .incomplete(.bundled))
        }
    }

    func testResolverPicksFirstUsableSource() async {
        let r2 = await ShowerProfileResolver.firstUsable([.bundled, .imported(fileName: "a.waterconfig")], provider: Provider())
        guard case .success(.local(let p, _)) = r2 else { return XCTFail() }
        XCTAssertEqual(p.version, "2")
        let r3 = await ShowerProfileResolver.firstUsable([.bundled], provider: Provider())
        XCTAssertEqual(r3, .failure(.missing(.bundled)))
    }
}
