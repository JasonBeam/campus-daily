import XCTest
import Core

/// 故障排查 › 导出热水诊断: the version, the time and where the hot-water record stands; no account,
/// key, device id, frame or time of the shower.
final class ShowerDiagnosticReportTests: XCTestCase {
    private let zone = TimeZone(identifier:"Asia/Shanghai")!
    private var now: Date {
        DateComponents(calendar:Calendar(identifier:.gregorian), timeZone:zone, year:2026, month:11, day:10, hour:21, minute:5).date!
    }

    func testCopy() {
        XCTAssertEqual(ShowerDiagnosticReport.title, "导出热水诊断")
        XCTAssertEqual(ShowerDiagnosticReport.footer, "仅检查已保存会话。诊断包含版本、时间和热水记录的状态，不含账号、密钥或设备编号。")
        XCTAssertEqual(ShowerDiagnosticReport.failed, "诊断文件暂未生成")
    }

    func testFileName() {
        XCTAssertEqual(ShowerDiagnosticReport.fileName(at:now, timeZone:zone), "校日常热水诊断 2026-11-10 2105.txt")
    }

    func testIdleRecord() {
        let text = ShowerDiagnosticReport.text(version:"0.9.0", build:"53", now:now, timeZone:zone, bound:true, state:ShowerState())
        XCTAssertEqual(text, """
        校日常热水诊断
        版本 0.9.0 (53)
        时间 2026-11-10 21:05
        水控 已绑定
        记录 phase=idle

        """)
    }

    func testRecordWaitingForReviewKeepsNoIds() {
        var state = ShowerState(phase:.running, machineID:"M-123456", peripheralID:"P-ABCDEF", startedAt:now,
                                authorizationID:"AUTH-9", consumption:"A1B2C3", stateReviewRequired:true)
        state.waitingForRelease = true
        let text = ShowerDiagnosticReport.text(version:nil, build:nil, now:now, timeZone:zone, bound:true, state:state)
        XCTAssertTrue(text.contains("记录 phase=running stateReviewRequired waitingForRelease"), text)
        XCTAssertTrue(text.contains("版本 — (—)"), text)
        for secret in ["M-123456", "P-ABCDEF", "AUTH-9", "A1B2C3"] { XCTAssertFalse(text.contains(secret), secret) }
    }

    func testNoRecord() {
        let text = ShowerDiagnosticReport.text(version:"0.9.0", build:"53", now:now, timeZone:zone, bound:false, state:nil)
        XCTAssertTrue(text.contains("水控 未绑定\n记录 无\n"), text)
    }

    func testWriteAndRemove() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory:true)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let folder = ShowerDiagnosticReport.directory(in:temporary)
        let url = try XCTUnwrap(ShowerDiagnosticReport.write("abc", into:folder, now:now, timeZone:zone))
        XCTAssertEqual(url.lastPathComponent, "校日常热水诊断 2026-11-10 2105.txt")
        XCTAssertEqual(try String(contentsOf:url, encoding:.utf8), "abc")
        ShowerDiagnosticReport.remove(in:folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath:folder.path))
    }
}
