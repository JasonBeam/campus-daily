import XCTest
import Foundation
@testable import Core
import CoreTestSupport

/// Shared synthetic values (match `Tests/Fixtures/ujing/*`).
enum L {
    static let qr = "https://q.ujing.com.cn/ucqrc/index.html?cd=000000000000000001"
    static let device = "test-device-0001"
    static let orderID = "TESTORDER0001"
    static let mobileID = "00000000-0000-4000-8000-000000000001"
    static let token = "test.synthetic-ujing-token.not-a-real-jwt-0000"
    static let base = "https://phoenix.ujing.online"
    static let t0 = Date(timeIntervalSince1970: 1_793_332_800) // 2026-10-30T12:00:00+08:00 (fixture createAt is +5 s)

    static let standard = WasherProgram(id: 1, name: "标准洗", minutes: 45, price: Money(fen: 400))
    static let quick = WasherProgram(id: 2, name: "快速洗", minutes: 25, price: Money(fen: 250))

    static func snapshot(status: Int = 0, enabled: Bool = true, active: String? = nil, at: Date = t0,
                         programs: [WasherProgram] = [standard, quick]) -> WasherSnapshot {
        WasherSnapshot(qrCode: qr,
                       scan: WasherScan(deviceID: device, moduleType: 7, status: status, createOrderEnabled: enabled, activeOrderID: active),
                       info: WasherInfo(deviceID: device, deviceNo: "测试洗衣机01", typeName: "滚筒洗衣机", storeName: "示例洗衣房",
                                        storeID: "test-store-01", deviceTypeID: 1, moduleType: 7, programs: programs),
                       fetchedAt: at)
    }

    static var draft: LaundryDraft { LaundryDraft.make(snapshot(), program: standard, now: t0)! }

    static func order(_ status: String, paid: Bool? = nil, price: Int? = 400, id: String = orderID, device: String = device,
                      program: Int? = 1, remain: Int? = nil, createdAt: String? = "2026-10-30T12:00:05+08:00") -> LaundryOrder {
        LaundryOrder(id: id, deviceID: device, status: LaundryOrderStatus(status),
                     paid: paid ?? !["10", "17", "53", "51"].contains(status), remainSeconds: remain, programID: program,
                     createdAt: createdAt, price: price.map { Money(fen: $0) })
    }

    static func client(_ server: StubServer, token: String? = token, log: HTTPLogSink = RecordingLogSink()) -> UjingClient {
        UjingClient(http: server.makeClient(allowedHosts: AllowedHosts.laundry, log: log),
                    device: UjingDevice(mobileID: mobileID, userAgent: "XiaoRiChang/test"), token: token)
    }

    static func json(_ s: String) -> Data { Data(s.utf8) }

    static func expectError(_ expected: ServiceError, file: StaticString = #filePath, line: UInt = #line,
                            _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let e as ServiceError {
            XCTAssertEqual(e, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}
