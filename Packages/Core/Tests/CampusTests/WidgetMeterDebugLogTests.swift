//
//  WidgetMeterDebugLogTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
@testable import Core
import CoreTestSupport

/// The widget's own meter read goes to the TestFlight debug log through the App Group
/// (`WidgetDebugLog`): a `role=widget` line with the app's salt once the app shared it, and
/// nothing at all before that (App Store, Xcode, the sample).
final class WidgetMeterDebugLogTests: XCTestCase {
    func widgetRead(_ log: WidgetDebugLog) async throws {
        var h = Harness()
        h.debugLog = log
        h.createsLoginDeviceID = false
        try h.signedIn(meter: Harness.roomBinding)
        try h.server.serve("ecykt/getSysBindCustInfo-ok")
        try h.server.serve("ecykt/getUserBalance-ok")
        try h.server.serve("ecykt/electric-getMeterStatus-room", matchBody: ["server", "buildingID"])
        try h.server.serve("ecykt/card-getRecordList-ok")
        let reading = await h.session().refresh(inBackground: true, owning: .unchecked)
        XCTAssertEqual(reading.outcome, .ok)
        log.flush()
    }

    func testAWidgetMeterReadWritesAWidgetLineOnTestFlight() async throws {
        let dir = DebugLogTesting.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let group = dir.appendingPathComponent("group/DebugLog", isDirectory: true)
        let app = FileDebugLog(directory: FileDebugLog.directory(in: dir.appendingPathComponent("app")), shared: group)
        app.shareSalt()
        app.flush()
        let widget = WidgetDebugLog(folder: group)
        XCTAssertTrue(widget.isEnabled)

        try await widgetRead(widget)

        let line = try XCTUnwrap(app.lines().first { $0.contains("school.meter") }, "the app's log has the widget's line")
        let tag = app.tag(DebugTag(.meter, "000000000991"))
        XCTAssertTrue(line.hasSuffix("school.meter role=widget meter=\(tag) reading=1234.56 at=10-30T08:10:22 kwh=52 fen=3692 price=0.71 days=3.2"),
                      "the same salt as the app's: \(line)")
        XCTAssertEqual(DebugLogTesting.leaks(["000000000991", "991001001000109000001003", "99栋"], in: app.lines().joined()), [])
    }

    func testNoLineAndNoFileWithoutTheAppsSalt() async throws {
        let dir = DebugLogTesting.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let group = dir.appendingPathComponent("group/DebugLog", isDirectory: true)
        let widget = WidgetDebugLog(folder: group)
        XCTAssertFalse(widget.isEnabled)

        try await widgetRead(widget)

        XCTAssertFalse(FileManager.default.fileExists(atPath: group.path), "nothing created")
    }
}
