import XCTest
import Core

/// The shared error words name the school only for the school's own systems.
final class ServiceErrorTextTests: XCTestCase {
    func testUjingAndHotWaterErrorsDoNotBlameTheSchool() {
        for error in [ServiceError.timedOut, .rejected(.ujing, code: "HTTP 500", message: ""),
                      .rejected(.lxt6, code: "HTTP 500", message: ""), .rejected(.feedback, code: "HTTP 500", message: "")] {
            XCTAssertFalse(error.userMessage.contains("学校"), "\(error): \(error.userMessage)")
        }
        XCTAssertTrue(ServiceError.rejected(.ujing, code: "HTTP 500", message: "").userMessage.contains("U净"))
    }

    func testSchoolRefusalsStillSaySchool() {
        for service in [Service.cas, .portal, .ecykt] {
            XCTAssertTrue(ServiceError.rejected(service, code: "HTTP 500", message: "").userMessage.contains("学校"), "\(service)")
        }
        XCTAssertEqual(ServiceError.rejected(.ujing, code: "1", message: "机器忙").userMessage, "机器忙", "the server's own words win")
    }
}
