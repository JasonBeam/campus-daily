import XCTest
import Core
import CoreTestSupport

/// Leaving the sample shows the live root again: on a fresh install its first-run check asks for
/// the guide at once, and 去登录 or a login link asks again a moment later. The second ask must
/// not replace the guide already up: a replaced cover or sheet is dismissed (which marks the
/// setup seen) and presented again.
@MainActor
final class GuideRequestTests: XCTestCase {
    private enum Step: Equatable { case login, washer }

    /// 暖橙: first-run and the login link both ask for the login step: one presentation.
    func testSecondAskForTheSameStepKeepsThePresentation() {
        let first = GuideRequest<Step>.ask(.login, over: nil)
        let second = GuideRequest<Step>.ask(.login, over: first)
        XCTAssertEqual(second, first)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.contentID, first.contentID)
    }

    /// 清爽: first-run opens the checklist, the login link then asks for 学校账号 on it: the same
    /// sheet (same id), its content started again with that row pushed.
    func testMoreSpecificAskUpdatesTheGuideInPlace() {
        let first = GuideRequest<SetupChecklist.Row>.ask(nil, over: nil)
        let second = GuideRequest<SetupChecklist.Row>.ask(.account, over: first)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.start, .account)
        XCTAssertNotEqual(second.contentID, first.contentID)
        // The other order: first-run after the link keeps 学校账号.
        let third = GuideRequest<SetupChecklist.Row>.ask(nil, over: second)
        XCTAssertEqual(third, second)
    }

    /// Once closed (nothing up), the next ask is a new presentation.
    func testAskAfterCloseIsANewPresentation() {
        let first = GuideRequest<Step>.ask(.login, over: nil)
        let next = GuideRequest<Step>.ask(.login, over: nil)
        XCTAssertNotEqual(next.id, first.id)
    }

    /// Out of the sample onto a fresh install by 去登录, with or without a login link (a widget)
    /// that came in while it was shown and waited for it.
    /// Each time the live root is built again and asks (first-run as it appears unless the kept
    /// link holds it, then the login or its link a moment later), and presents once; no ask dismisses the guide, so 「seen」 is not
    /// written for it.
    func testLeavingTheSampleOpensTheGuideOnce() throws {
        let login = try XCTUnwrap(URL(string: "campusdaily://login"))
        let ways: [@MainActor (SampleMode) -> Bool] = [
            { $0.leave(); return $0.takeLogin() },
            // The kept login link is the one destination: no login step due besides it.
            { _ = $0.open(login); $0.leave(); return !$0.takeLogin() && $0.takePendingLink() == .login },
        ]
        for leave in ways {
            let sample = SampleMode.overIdleShower()
            let seen = SeenCounter()
            var shown: GuideRequest<Step>?   // the live root's, new after the sample
            var presentations = 0
            func ask(_ step: Step) {
                let next = GuideRequest<Step>.ask(step, over: shown)
                if let old = shown, old.id != next.id { QuickSetupSeen.closed(in: seen, coveredBySample: sample.isActive) }
                if shown?.id != next.id { presentations += 1 }
                shown = next
            }
            sample.enter()
            let due = leave(sample)
            XCTAssertFalse(sample.isActive)
            if !sample.firstRunHeld { ask(.login) }  // first-run, as the live root appears
            XCTAssertTrue(due); ask(.login)  // the login asked for on the way out (or its link)
            XCTAssertEqual(presentations, 1)
            XCTAssertEqual(seen.writes, 0)
        }
    }

    /// The guide moved on past the page a link asks for (暖橙: from 登录 to 洗衣机; 清爽: from
    /// 学校账号 to 宿舍): the link takes it back there, on the same presentation (no new cover or
    /// sheet, so nothing marks the setup seen). Asked for the page it is on, or for its first
    /// page (first-run), it stays.
    func testAskForAPageTheGuideMovedOffGoesBackToIt() {
        let seen = SeenCounter()
        var shown = GuideRequest<Step>.ask(.login, over: nil)
        let opened = shown
        shown.moved(to: .washer)
        XCTAssertEqual(shown.id, opened.id)
        XCTAssertEqual(shown.contentID, opened.contentID, "moving inside the guide does not restart it")
        let back = GuideRequest<Step>.ask(.login, over: shown)
        XCTAssertEqual(back.id, opened.id)
        XCTAssertNotEqual(back.contentID, shown.contentID)
        XCTAssertEqual(back.start, .login)
        if back.id != shown.id { QuickSetupSeen.closed(in: seen, coveredBySample: false) }
        XCTAssertEqual(seen.writes, 0)
        // On the login page already: nothing changes.
        XCTAssertEqual(GuideRequest<Step>.ask(.login, over: back), back)

        var sheet = GuideRequest<SetupChecklist.Row>.ask(.account, over: nil)
        sheet.moved(to: .dorm)
        let account = GuideRequest<SetupChecklist.Row>.ask(.account, over: sheet)
        XCTAssertEqual(account.id, sheet.id)
        XCTAssertNotEqual(account.contentID, sheet.contentID)
        XCTAssertEqual(account.start, .account)
        // First-run asking while the checklist is on 宿舍: it stays there.
        XCTAssertEqual(GuideRequest<SetupChecklist.Row>.ask(nil, over: sheet), sheet)
        // Back on the checklist itself, a link to 学校账号 pushes it again.
        var list = account
        list.moved(to: nil)
        XCTAssertNotEqual(GuideRequest<SetupChecklist.Row>.ask(.account, over: list).contentID, list.contentID)
    }
}

private final class SeenCounter: PreferenceStorage {
    var writes = 0
    func object(forKey key: String) -> Any? { nil }
    func set(_ value: Any?, forKey key: String) { writes += 1 }
}
