import XCTest
import Core

final class CampusLoginProgressTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970:1_700_000_000)

    func testHiddenUntilTheFormShows() {
        var p = CampusLoginProgress(now:t0)
        XCTAssertTrue(p.concealed)
        XCTAssertEqual(p.text, "正在打开学校登录…")
        p.pageStarted(host:"cas.gdbtu.edu.cn", now:t0)
        p.probed(automation:"login", formVisible:false, now:t0.addingTimeInterval(1))
        XCTAssertTrue(p.concealed, "sign-in host without its form (redirect page) stays hidden")
        p.probed(automation:"login", formVisible:true, now:t0.addingTimeInterval(2))
        XCTAssertFalse(p.concealed)
        XCTAssertNil(p.text)
        // A failed password reloads the sign-in page: it stays visible.
        p.pageStarted(host:"cas.gdbtu.edu.cn", now:t0.addingTimeInterval(3))
        p.probed(automation:"login", formVisible:false, now:t0.addingTimeInterval(3))
        XCTAssertFalse(p.concealed)
    }

    func testStagesInOrderAndNeverBack() {
        var p = CampusLoginProgress(now:t0)
        p.probed(automation:"login", formVisible:true, now:t0)
        var shown: [String] = []
        func note() { if let text = p.text, shown.last != text { shown.append(text) } }
        p.pageStarted(host:"portal.gdbtu.edu.cn", now:t0); note()
        for stage in ["waiting-portal", "portal-profile", "waiting-profile", "opening-wallet", "waiting-portal", "waiting-wallet", "wallet-ready"] {
            p.probed(automation:stage, formVisible:false, now:t0); note()
        }
        p.pageStarted(host:"portal.gdbtu.edu.cn", now:t0); note()
        p.delivered(now:t0); note()
        XCTAssertEqual(shown, ["正在登录学校账号…", "正在读校园卡…", "正在读电量…"])
        XCTAssertTrue(p.concealed)
    }

    func testUserFacingTextAvoidsInternalNames() {
        let all = [CampusLoginProgress.openingText, CampusLoginProgress.slowText] + CampusLoginProgress.Stage.allCases.map(CampusLoginProgress.text)
        for text in all {
            XCTAssertFalse(text.contains("门户"), text)
            XCTAssertFalse(text.contains("一卡通"), text)
        }
    }

    func testSlowNoteAfterEightSecondsPerStage() {
        var p = CampusLoginProgress(now:t0)
        XCTAssertNil(p.slowNote(now:t0.addingTimeInterval(8)))
        XCTAssertEqual(p.slowNote(now:t0.addingTimeInterval(8.5)), "学校网站有点慢，再等一会儿。")
        p.pageStarted(host:"ecykt.gdbtu.edu.cn", now:t0.addingTimeInterval(9))
        XCTAssertNil(p.slowNote(now:t0.addingTimeInterval(12)), "a new stage restarts the clock")
        XCTAssertNotNil(p.slowNote(now:t0.addingTimeInterval(17.1)))
        p.probed(automation:"waiting-portal", formVisible:false, now:t0.addingTimeInterval(18))
        XCTAssertNotNil(p.slowNote(now:t0.addingTimeInterval(18)), "an earlier stage doesn't reset the clock")
    }

    func testOpeningFallbacks() {
        var p = CampusLoginProgress(now:t0)
        p.tick(now:t0.addingTimeInterval(14))
        XCTAssertTrue(p.concealed)
        p.tick(now:t0.addingTimeInterval(15.5))
        XCTAssertFalse(p.concealed, "no form after 15 s: show the page anyway")

        var q = CampusLoginProgress(now:t0)
        q.failed(now:t0)
        XCTAssertFalse(q.concealed, "load failure shows the page and its error line")

        // Sent back to the sign-in host after signing in: hidden until the form shows again.
        var r = CampusLoginProgress(now:t0)
        r.probed(automation:"login", formVisible:true, now:t0)
        r.pageStarted(host:"portal.gdbtu.edu.cn", now:t0)
        r.pageStarted(host:"cas.gdbtu.edu.cn", now:t0)
        XCTAssertEqual(r.phase, .opening)
        XCTAssertNil(CampusLoginProgress.stage(automation:"unsupported-origin"))
    }
}
