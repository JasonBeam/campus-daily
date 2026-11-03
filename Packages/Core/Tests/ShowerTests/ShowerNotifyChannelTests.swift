import XCTest
@testable import Core
import CoreTestSupport

/// The kept link's notify channel: only a reply inside an exchange counts. A notification the
/// controller sends while nothing was asked must not become the next command's reply or block it.
final class ShowerNotifyChannelTests: XCTestCase {
    func testANotificationOutsideAnExchangeIsIgnored() {
        var channel = ShowerNotifyChannel()
        XCTAssertEqual(channel.receive(FakeFrames.active, failed: false, inExchange: false), .ignored)
        XCTAssertEqual(channel.receive(FakeFrames.active, failed: false, inExchange: false), .ignored)
        XCTAssertEqual(channel.receive(nil, failed: true, inExchange: false), .ignored)
        XCTAssertEqual(channel.receive(Data([0x00]), failed: false, inExchange: false), .ignored)
        XCTAssertNil(channel.blocker, "the next exchange may start")
        XCTAssertEqual(channel.receive(FakeFrames.ack, failed: false, inExchange: true), .frame)
        XCTAssertEqual(channel.take(), FakeFrames.ack)
        XCTAssertNil(channel.take())
    }

    func testAReplyInsideAnExchange() {
        var channel = ShowerNotifyChannel()
        let identity = FakeFrames.identity("11223344")
        XCTAssertEqual(channel.receive(identity.prefix(5), failed: false, inExchange: true), .partial)
        XCTAssertEqual(channel.blocker, .disconnected, "half a frame blocks the next write")
        XCTAssertEqual(channel.receive(identity.dropFirst(5), failed: false, inExchange: true), .frame)
        XCTAssertEqual(channel.take(), identity)
        XCTAssertNil(channel.blocker)
    }

    func testAChannelErrorInsideAnExchangeBlocksUntilTheLinkIsReused() {
        var channel = ShowerNotifyChannel()
        XCTAssertEqual(channel.receive(FakeFrames.active, failed: false, inExchange: true), .frame)
        XCTAssertEqual(channel.receive(FakeFrames.active, failed: false, inExchange: true), .failed(.malformedFrame))
        XCTAssertEqual(channel.blocker, .malformedFrame)
        channel.reset()
        XCTAssertNil(channel.blocker, "a reused link starts clean")

        XCTAssertEqual(channel.receive(nil, failed: true, inExchange: true), .failed(.disconnected))
        XCTAssertEqual(channel.blocker, .disconnected)
        channel.reset()
        XCTAssertNil(channel.blocker)
        XCTAssertNil(channel.take())
    }

    func testTwoFramesInOneNotificationAreMalformed() {
        var channel = ShowerNotifyChannel()
        XCTAssertEqual(channel.receive(FakeFrames.ack + FakeFrames.active, failed: false, inExchange: true), .failed(.malformedFrame))
        XCTAssertNil(channel.take())
    }
}
