//
//  RefusalReplyNoteTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/17.
//

import XCTest
@testable import Core
import CoreTestSupport

/// The CAS password POST and ecykt's getSignData note in the request log what kind of refusal
/// came back, as one fixed word: never the page's or the server's words, the account, ids or
/// anything typed.
final class RefusalReplyNoteTests: XCTestCase {
    let account = "99100991", password = "synthetic-pw-991"

    func submitNote(status: Int, body: Data) async throws -> HTTPLogEntry? {
        let server = StubServer(), sink = RecordingLogSink()
        let (_, pem) = try CASFake.keyPair()
        CASFake.serveForm(server, pem: pem)
        server.respond("POST", CASFake.loginURL, status: status, headers: ["Content-Type": "text/html"], body: body)
        _ = try? await CASLoginClient(http: server.makeClient(log: sink)).login(account: account, password: password, visitorID: CASFake.visitor)
        return sink.entries.first { $0.name == "casLoginSubmit" }
    }

    func testTheCASPasswordPostNotesWhatKindOfRefusalItWas() async throws {
        let wrong = #"<div id="msg" class="errors"><p>用户名或者密码错误，学号 99100991 再错 3 次将被锁定</p></div>"#
        let cases: [(Int, Data, HTTPReplyNote)] = [
            (401, CASWrongPasswordPageTests.refusedPage(wrong), .casWrong),
            (200, CASFake.page(errors: #"["账号已锁定，请 30 分钟后再试"]"#), .casBlocked),
            (200, CASFake.page(errors: #"["请使用短信验证登录"]"#), .casSoftBlocked),
            (401, CASFake.page(errors: #"["认证失败"]"#), .casVagueWrong),
            (401, CASWrongPasswordPageTests.refusedPage(#"<div class="alert alert-danger">出了点问题 123456789</div>"#), .casUnrecognised),
            (200, CASFake.page(), .casNoError),
        ]
        for (status, body, note) in cases {
            let entry = try await submitNote(status: status, body: body)
            XCTAssertEqual(entry?.status, status)
            XCTAssertEqual(entry?.note, note)
            let line = DebugEvent.http(DebugHTTP(try XCTUnwrap(entry))).fields { _ in "tag" }
            XCTAssertTrue(line.hasSuffix(" note=\(note.rawValue)"), line)
            XCTAssertTrue(DebugLogTesting.leaks([account, password, "99100991", "123456789", "密码", "锁定", "问题"], in: line).isEmpty, line)
        }
    }

    func testOtherCASAnswersHaveNoNote() async throws {
        XCTAssertNil(CASPage.replyNote(status: 302, body: CASFake.page(errors: #"["密码错误"]"#)))
        XCTAssertNil(CASPage.replyNote(status: 503, body: CASFake.page(errors: #"["密码错误"]"#)))
        let entry = try await submitNote(status: 503, body: Data("busy".utf8))
        XCTAssertNotNil(entry)
        XCTAssertNil(entry?.note)
    }

    func testEcyktGetSignDataNotesTheKindOfMessage() async throws {
        let url = SchoolEndpoints.ecyktBase.absoluteString + "/api/customer/getSignData"
        for (body, note) in [(#"{"code":"500","msg":"账户余额不足 卡号 20230012345","data":null}"#, HTTPReplyNote.msgBalance),
                             (#"{"code":"7","msg":"系统维护 20230012345"}"#, .msgOther),
                             (#"{"code":"7","msg":""}"#, .msgEmpty)] {
            let server = StubServer(), sink = RecordingLogSink()
            server.respond("POST", url, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
            _ = try? await EcyktClient(http: server.makeClient(log: sink)).signData(T.session(), custid: T.custid)
            let entry = try XCTUnwrap(sink.entries.first { $0.name == "getSignData" })
            XCTAssertEqual(entry.note, note, body)
            let line = DebugEvent.http(DebugHTTP(entry)).fields { _ in "tag" }
            XCTAssertTrue(DebugLogTesting.leaks(["20230012345", "余额", "维护"], in: line).isEmpty, line)
        }
    }
}
