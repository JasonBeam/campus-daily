import XCTest
@testable import XiaoRiChang

/// Crash reports start at launch from the feedback key and the crash endpoint in Info.plist, and
/// not at all when either is missing.
final class CrashReportsLaunchTests: XCTestCase {
    private let endpoint = "https://feedback.example.test/v1/ingest/crashes"

    func testTheAppDeclaresTheKeyAndTheCrashEndpoint() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertNotNil(info["FeedbackAppKey"] as? String)
        XCTAssertNotNil(info["FeedbackCrashEndpoint"] as? String)
    }

    func testTheBuiltAppStartsOnlyWithBothValues() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = info["FeedbackAppKey"] as? String ?? ""
        let endpoint = info["FeedbackCrashEndpoint"] as? String ?? ""
        let launch = CrashReportsLaunch(info: info)
        if key.isEmpty || endpoint.isEmpty {
            XCTAssertNil(launch)
        } else {
            XCTAssertEqual(launch, CrashReportsLaunch(info: ["FeedbackAppKey": key, "FeedbackCrashEndpoint": endpoint]))
            XCTAssertEqual(launch?.apiKey, key)
            XCTAssertEqual(launch?.endpoint, endpoint)
        }
    }

    func testBothValuesStartReportsOnce() {
        var calls: [[String]] = []
        let started = CrashReportsLaunch.start(info: ["FeedbackAppKey": "ak_test", "FeedbackCrashEndpoint": endpoint]) {
            calls.append([$0, $1])
        }
        XCTAssertTrue(started)
        XCTAssertEqual(calls, [["ak_test", endpoint]])
    }

    func testAnEmptyOrMissingValueSkipsTheStart() {
        let cases: [[String: Any]] = [
            [:],
            ["FeedbackAppKey": "", "FeedbackCrashEndpoint": endpoint],
            ["FeedbackAppKey": "ak_test", "FeedbackCrashEndpoint": ""],
            ["FeedbackAppKey": "ak_test"],
            ["FeedbackCrashEndpoint": endpoint],
            // An unexpanded or plain-HTTP value is no endpoint either.
            ["FeedbackAppKey": "ak_test", "FeedbackCrashEndpoint": "$(FEEDBACK_CRASH_ENDPOINT)"],
            ["FeedbackAppKey": "ak_test", "FeedbackCrashEndpoint": "http://feedback.example.test/v1/ingest/crashes"],
        ]
        for info in cases {
            var called = false
            XCTAssertFalse(CrashReportsLaunch.start(info: info) { _, _ in called = true }, "\(info)")
            XCTAssertFalse(called, "\(info)")
            XCTAssertNil(CrashReportsLaunch(info: info), "\(info)")
        }
    }
}
