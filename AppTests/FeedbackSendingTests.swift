//
//  FeedbackSendingTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import Combine
import UIKit
import XCTest
import Core
@testable import XiaoRiChang

/// The feedback form's send: the slow line after 5 s, 取消 stopping the request without a word,
/// the failure line (with or without screenshots), and the screenshots' size.
@MainActor
final class FeedbackSendingTests: XCTestCase {
    /// A clock whose waits end only when the test says so.
    private final class Clock: @unchecked Sendable {
        // @unchecked: guarded by `lock`.
        private let lock = NSLock()
        private var waits: [TimeInterval] = []
        private var passed = false
        var asked: [TimeInterval] { lock.withLock { waits } }
        func pass() { lock.withLock { passed = true } }
        var sleep: @Sendable (TimeInterval) async throws -> Void {
            { [self] seconds in
                lock.withLock { waits.append(seconds) }
                while !lock.withLock({ passed }) { try await Task.sleep(for:.milliseconds(1)) }
            }
        }
    }

    /// A send that never ends on its own, and whether it was cancelled.
    private final class Hanging: @unchecked Sendable {
        private let lock = NSLock()
        private var _started = false, _cancelled = false
        var started: Bool { lock.withLock { _started } }
        var cancelled: Bool { lock.withLock { _cancelled } }
        var send: @MainActor @Sendable () async throws -> Void {
            { [self] in
                lock.withLock { _started = true }
                do { try await Task.sleep(for:.seconds(3600)) } catch {
                    lock.withLock { _cancelled = true }
                    throw CancellationError()
                }
            }
        }
    }

    /// The main-queue deadlines asked for, run when the test says so.
    private final class Deadlines {
        private(set) var asked: [(seconds: TimeInterval, item: DispatchWorkItem)] = []
        var schedule: (TimeInterval, DispatchWorkItem) -> Void { { [self] in asked.append(($0, $1)) } }
        func fire() { asked.forEach { $0.item.perform() } }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        var tries = 0
        while !condition(), tries < 2000 {
            tries += 1
            try await Task.sleep(for:.milliseconds(5))
        }
        XCTAssertTrue(condition(), "timed out", file:file, line:line)
    }

    func testTheSlowLineAppearsAfterFiveSecondsAndGoesWithTheSend() async throws {
        let clock = Clock(), hanging = Hanging()
        let model = FeedbackSending(sleep:clock.sleep)
        model.start(withScreenshots:false, clear:false, hanging.send)
        XCTAssertTrue(model.sending)
        try await waitUntil { clock.asked == [FeedbackText.slowAfter] && hanging.started }
        XCTAssertFalse(model.slow, "not before 5 s")
        clock.pass()
        try await waitUntil { model.slow }
        XCTAssertTrue(model.sending)
        model.cancel()
        XCTAssertFalse(model.slow, "the line goes when the send ends")
        XCTAssertFalse(model.sending)
    }

    /// The view announces the slow line when `slow` turns true: once per send, never again
    /// while that send runs, and once more for the next send.
    func testSlowTurnsOnOncePerSend() async throws {
        let clock = Clock()
        let model = FeedbackSending(sleep:clock.sleep, schedule:{ _, _ in })
        var turnedOn = 0
        let watch = model.$slow.removeDuplicates().dropFirst().filter { $0 }.sink { _ in turnedOn += 1 }
        defer { watch.cancel() }
        clock.pass()
        model.start(withScreenshots:false, clear:false, Hanging().send)
        try await waitUntil { model.slow }
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(turnedOn, 1)
        model.cancel()
        model.start(withScreenshots:false, clear:true, Hanging().send)
        try await waitUntil { model.slow }
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(turnedOn, 2, "once for each send")
        model.cancel()
    }

    func testAQuickSendNeverSaysSlow() async throws {
        let clock = Clock()
        let model = FeedbackSending(sleep:clock.sleep)
        model.start(withScreenshots:false, clear:true) {}
        try await waitUntil { model.sent }
        clock.pass()
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertFalse(model.slow)
        XCTAssertFalse(model.sending)
        XCTAssertNil(model.failure)
    }

    /// 取消 while sending: the request is cancelled, and neither a failure nor 发出去了 follows.
    func testCancelStopsTheSendWithoutAWord() async throws {
        let clock = Clock(), hanging = Hanging()
        let model = FeedbackSending(sleep:clock.sleep)
        model.start(withScreenshots:true, clear:false, hanging.send)
        try await waitUntil { hanging.started }
        model.cancel()
        XCTAssertFalse(model.sending)
        try await waitUntil { hanging.cancelled }
        clock.pass()
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.sent)
        XCTAssertFalse(model.slow)
    }

    /// A send that ends after 取消 anyway (its answer was already on the way) changes nothing.
    func testAnAnswerAfterCancelIsIgnored() async throws {
        let model = FeedbackSending(sleep:Clock().sleep)
        model.start(withScreenshots:false, clear:false) {
            try? await Task.sleep(for:.milliseconds(20))
            throw FeedbackFailure()
        }
        model.cancel()
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.sent)
    }

    func testTheFailureLineFollowsScreenshotsAndTheme() async throws {
        for (screenshots, clear, line) in [(false, false, FeedbackText.failureText),
                                           (false, true, FeedbackText.failureText),
                                           (true, false, "没发出去。网络慢的话，少带几张截图再试。"),
                                           (true, true, "发送失败；网络较慢时可减少截图后重试")] {
            let model = FeedbackSending(sleep:Clock().sleep)
            model.start(withScreenshots:screenshots, clear:clear) { throw FeedbackFailure() }
            try await waitUntil { !model.sending }
            XCTAssertEqual(model.failure, line, "\(screenshots) \(clear)")
            XCTAssertFalse(model.sent)
        }
    }

    func testSendingAgainClearsTheFailure() async throws {
        let model = FeedbackSending(sleep:Clock().sleep)
        model.start(withScreenshots:false, clear:false) { throw FeedbackFailure() }
        try await waitUntil { model.failure != nil }
        model.start(withScreenshots:false, clear:false) {}
        XCTAssertNil(model.failure)
        try await waitUntil { model.sent }
    }

    // MARK: The main-queue deadline

    func testTheDeadlineIsTheSendsLimitPlusTwoSeconds() {
        XCTAssertEqual(FeedbackSending.deadline(withScreenshots:false), 17)
        XCTAssertEqual(FeedbackSending.deadline(withScreenshots:true), 62)
        let deadlines = Deadlines()
        let model = FeedbackSending(sleep:Clock().sleep, schedule:deadlines.schedule)
        model.start(withScreenshots:true, clear:false, Hanging().send)
        XCTAssertEqual(deadlines.asked.map(\.seconds), [62])
        model.cancel()
        XCTAssertTrue(deadlines.asked[0].item.isCancelled, "cancelled with the send")
    }

    /// A send that never returns (nothing in Swift concurrency's pool runs for it): the deadline
    /// on the main queue stops it and shows the failure line for its screenshots and theme.
    func testTheDeadlineEndsASendThatNeverReturns() async throws {
        for (screenshots, clear, line) in [(false, false, FeedbackText.failureText),
                                           (true, false, "没发出去。网络慢的话，少带几张截图再试。"),
                                           (true, true, "发送失败；网络较慢时可减少截图后重试")] {
            let deadlines = Deadlines(), hanging = Hanging()
            let model = FeedbackSending(sleep:Clock().sleep, schedule:deadlines.schedule)
            model.start(withScreenshots:screenshots, clear:clear, hanging.send)
            try await waitUntil { hanging.started }
            deadlines.fire()
            XCTAssertFalse(model.sending)
            XCTAssertFalse(model.slow)
            XCTAssertEqual(model.failure, line, "\(screenshots) \(clear)")
            try await waitUntil { hanging.cancelled }
            try await Task.sleep(for:.milliseconds(50))
            XCTAssertEqual(model.failure, line, "the cancelled send's own end changes nothing")
            XCTAssertFalse(model.sent)
        }
    }

    /// The real main-queue timer, with the send's task never even started: fires on its own.
    func testTheDeadlineFiresOnTheMainQueue() async throws {
        let model = FeedbackSending(sleep:Clock().sleep, schedule:{ _, item in
            DispatchQueue.main.asyncAfter(deadline:.now() + 0.05, execute:item)
        })
        model.start(withScreenshots:false, clear:true, Hanging().send)
        try await waitUntil { model.failure != nil }
        XCTAssertEqual(model.failure, FeedbackText.failureText)
        XCTAssertFalse(model.sending)
    }

    /// A send that ended before the deadline: the deadline does nothing.
    func testTheDeadlineAfterTheSendEndedChangesNothing() async throws {
        let deadlines = Deadlines()
        let model = FeedbackSending(sleep:Clock().sleep, schedule:deadlines.schedule)
        model.start(withScreenshots:false, clear:false) {}
        try await waitUntil { model.sent }
        XCTAssertTrue(deadlines.asked[0].item.isCancelled)
        deadlines.fire()
        XCTAssertNil(model.failure)
        XCTAssertTrue(model.sent)
    }

    // MARK: Screenshots

    private func image(_ width: CGFloat, _ height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size:CGSize(width:width, height:height), format:format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x:0, y:0, width:width / 2, height:height))
        }
    }

    func testScreenshotsAreScaledTo1280OnTheLongSide() throws {
        XCTAssertEqual(FeedbackReporter.longestSide, 1280)
        XCTAssertEqual(FeedbackReporter.jpegQuality, 0.7)
        for (source, expected) in [(CGSize(width:1179, height:2556), CGSize(width:590, height:1280)),
                                   (CGSize(width:4032, height:3024), CGSize(width:1280, height:960)),
                                   (CGSize(width:800, height:600), CGSize(width:800, height:600))] {
            let data = try XCTUnwrap(FeedbackReporter.jpeg(image(source.width, source.height)))
            let decoded = try XCTUnwrap(UIImage(data:data))
            XCTAssertEqual(decoded.size, expected, "\(source)")
            XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]), "JPEG")
        }
    }
}
