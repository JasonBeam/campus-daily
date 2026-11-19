import XCTest
import Core

final class MoneyTests: XCTestCase {
    func testParsesYuanStrings() {
        XCTAssertEqual(Money(yuanString: "7.9")?.fen, 790)
        XCTAssertEqual(Money(yuanString: ".06")?.fen, 6)
        XCTAssertEqual(Money(yuanString: "213.38")?.fen, 21338)
        XCTAssertEqual(Money(yuanString: "-1.50")?.fen, -150)
        XCTAssertEqual(Money(yuanString: "0.005")?.fen, 1) // half away from zero
        XCTAssertEqual(Money(yuanString: " 12 ")?.fen, 1200)
        for bad in ["", "abc", "1,000.00", "1.2.3", "¥3", "NaN"] { XCTAssertNil(Money(yuanString: bad), bad) }
    }

    func testParsesJSONNumbersWithoutBinaryDrift() {
        XCTAssertEqual(Money(yuanNumber: 7.9)?.fen, 790)
        XCTAssertEqual(Money(yuanNumber: 0.1 + 0.2)?.fen, 30)
        XCTAssertEqual(Money(yuanNumber: 98.9)?.fen, 9890)
        XCTAssertNil(Money(yuanNumber: .infinity))
    }

    func testFormattingAndArithmetic() {
        XCTAssertEqual(Money(fen: 790).yuanText, "7.90")
        XCTAssertEqual(Money(fen: -6).yuanText, "-0.06")
        XCTAssertEqual((Money(fen: 100) - Money(fen: 790)).fen, -690)
        XCTAssertTrue(Money(fen: 1) < Money(fen: 2))
        XCTAssertEqual(DecimalText.parse("14896.4300"), Decimal(string: "14896.43", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertNil(DecimalText.parse("1,5"))
    }
}

final class ServiceErrorTests: XCTestCase {
    func testStateChangingRequestsBecomeUncertain() {
        for e: ServiceError in [.offline, .timedOut, .tls, .malformed(.lxt6, "data")] {
            XCTAssertEqual(e.forStateChangingRequest(.lxt6), .uncertain(.lxt6))
        }
        XCTAssertEqual(ServiceError.badRequest(.lxt6).forStateChangingRequest(.lxt6), .badRequest(.lxt6))
        XCTAssertEqual(ServiceError.sessionExpired(.ujing).forStateChangingRequest(.ujing), .sessionExpired(.ujing))
        let r = ServiceError.rejected(.lxt6, code: "1", message: "no")
        XCTAssertEqual(r.forStateChangingRequest(.lxt6), r)
    }

    func testRejectionTrimsMessage() {
        let long = String(repeating: "长", count: 200)
        guard case .rejected(_, _, let m) = ServiceError.rejection(.ecykt, code: "9", message: long) else { return XCTFail() }
        XCTAssertEqual(m.count, ServiceError.maxMessageLength)
    }
}

final class JSONValueTests: XCTestCase {
    func testParsesFragmentsAndKeepsIntegersExact() throws {
        XCTAssertEqual(try JSONValue.parse("7.9"), .double(7.9))
        XCTAssertEqual(try JSONValue.parse("997000000000000001"), .int(997000000000000001))
        XCTAssertEqual(try JSONValue.parse("\"[]\"").text, "[]")
        XCTAssertEqual(try JSONValue.parse("{\"a\":[true,null]}")["a"], .array([.bool(true), .null]))
    }
}
