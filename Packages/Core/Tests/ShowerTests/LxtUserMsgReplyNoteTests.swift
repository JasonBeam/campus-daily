//
//  LxtUserMsgReplyNoteTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/17.
//

import XCTest
@testable import Core
import CoreTestSupport

/// getUserMsg notes in the request log what kind of message came with a refusal code (one fixed
/// word, never the message); other reads note nothing.
final class LxtUserMsgReplyNoteTests: XCTestCase {
    let userMsg = "https://isv.lxt6.cn/AECC/GDBusinessSchool/getUserMsg"

    func entry(_ url: String, _ body: String, read: (LxtClient) async throws -> Void) async throws -> HTTPLogEntry {
        let server = StubServer(), sink = RecordingLogSink()
        server.respond("GET", url, headers: ["Content-Type": "text/html;charset=UTF-8"], body: Data(body.utf8))
        let client = LxtClient(http: server.makeClient(allowedHosts: AllowedHosts.hotWater, log: sink), profile: Golden.profile,
                               random: { $0 == LxtSigning.userMsgAlphabet ? "ABC123" : "A1B2C3" })
        try? await read(client)
        return try XCTUnwrap(sink.entries.last)
    }

    func testGetUserMsgNotesTheKindOfMessage() async throws {
        let cases: [(String, HTTPReplyNote?)] = [
            (#"{"Code":1,"Message":"账户余额不足，请充值后使用 991000000000000001"}"#, .msgBalance),
            (#""{\"code\":2,\"message\":\"欠费\"}""#, .msgBalance),
            (#"{"Code":1,"Message":"系统繁忙 991000000000000001"}"#, .msgOther),
            (#"{"Code":1}"#, .msgEmpty),
            (#"{"Code":0,"Message":"成功","Data":{"schoolid":20021,"studentid":"991000000000000001"}}"#, nil),
        ]
        for (body, note) in cases {
            let e = try await entry(userMsg, body) { _ = try await $0.userInfo(Golden.handoff) }
            XCTAssertEqual(e.name, "getUserMsg")
            XCTAssertEqual(e.note, note, body)
            let line = DebugEvent.http(DebugHTTP(e)).fields { _ in "tag" }
            XCTAssertTrue(DebugLogTesting.leaks(["991000000000000001", "余额", "繁忙", "欠费"], in: line).isEmpty, line)
        }
    }

    func testOtherReadsNoteNothing() async throws {
        let areas = "https://isv.lxt6.cn/AECC/GDBusinessSchool/getAreaInfoForApplests"
        let e = try await entry(areas, #"{"Code":1,"Message":"账户余额不足"}"#) { _ = try await $0.areas(parent: "20021") }
        XCTAssertNil(e.note)
    }
}
