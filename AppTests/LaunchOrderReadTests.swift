import XCTest
import Core
@testable import XiaoRiChang

/// A user launch (`LaunchReads`, the scene's launch `.task`) reads the open laundry order, the
/// way coming back to the app does: a paid 立刻洗衣 order is started there under the engine's
/// usual rules (in front, the account that placed it, the 10-minute window, the price), and
/// never a second time. On fake stores and a scripted U净.
@MainActor
final class LaunchOrderReadTests: XCTestCase {
    /// Paid, 立刻洗衣, placed a minute ago, the app in front: the launch sends one start. Coming
    /// to the front again (the scene's `.active` read) or reading the order again sends no other.
    func testALaunchStartsAPaidImmediateOrderOnce() async throws {
        let ujing = ScriptedUjing()
        let (campus, laundry) = launchModels(record: Self.paidImmediate(), ujing: ujing, inFront: { true })

        await LaunchReads.run(campus: campus, laundry: laundry)
        await waitUntil { !laundry.checkoutBusy }

        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(Self.orderID)), 1, "the launch read starts it")
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(Self.orderID)), 1)
        XCTAssertEqual(laundry.checkout?.phase, .active)
        XCTAssertEqual(laundry.checkout?.start, .started, "started, then read washing")

        // The scene becomes `.active` (`LiveAppHooks`), then the laundry page reads it.
        await laundry.refreshOrder()
        await laundry.refreshOrder()
        await waitUntil { !laundry.checkoutBusy }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(Self.orderID)), 1, "never a second start")
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(Self.orderID)), 1)
    }

    /// No order open: the launch reads the machine only, nothing about an order.
    func testALaunchWithNoOrderReadsNoOrder() async throws {
        let ujing = ScriptedUjing()
        let (campus, laundry) = launchModels(record: nil, ujing: ujing, inFront: { true })

        await LaunchReads.run(campus: campus, laundry: laundry)
        await waitUntil { !laundry.checkoutBusy }

        XCTAssertEqual(ujing.orderRequests, [], "no order read, no start")
        XCTAssertEqual(laundry.checkout?.phase ?? LaundryPhase.none, LaundryPhase.none)
    }

    /// Launched but not in front: the order is read, nothing is started; once the app is in
    /// front, its read starts it, once.
    func testALaunchOutOfFrontStartsNothingUntilInFront() async throws {
        let ujing = ScriptedUjing()
        let front = FrontFlag()
        let (campus, laundry) = launchModels(record: Self.paidImmediate(), ujing: ujing, inFront: { front.value })

        await LaunchReads.run(campus: campus, laundry: laundry)
        await waitUntil { !laundry.checkoutBusy }

        XCTAssertEqual(ujing.count(UjingEndpoints.detail(Self.orderID)), 1, "the launch read the order")
        XCTAssertEqual(ujing.count(UjingEndpoints.startCheck(Self.orderID)), 0, "not in front: no pre-start read")
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(Self.orderID)), 0, "not in front: no start")
        XCTAssertNil(laundry.checkout?.start, "still to be tried")

        front.value = true
        await laundry.refreshOrder()  // the scene becomes `.active`
        await waitUntil { !laundry.checkoutBusy && ujing.count(UjingEndpoints.startWasher(Self.orderID)) > 0 }
        await waitUntil { !laundry.checkoutBusy }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(Self.orderID)), 1)

        await laundry.refreshOrder()
        await waitUntil { !laundry.checkoutBusy }
        XCTAssertEqual(ujing.count(UjingEndpoints.startWasher(Self.orderID)), 1, "never a second start")
    }

    // MARK: Fixtures

    nonisolated static let orderID = "TESTORDER0001"
    nonisolated static let accountID = "test-account-1"
    nonisolated static let device = "test-device-0001"
    nonisolated static let qr = "https://q.ujing.com.cn/ucqrc/index.html?cd=000000000000000001"
    nonisolated static let program = WasherProgram(id: 1, name: "标准洗", minutes: 45, price: Money(fen: 400))

    /// What a phone killed while checking the payment keeps: 立刻洗衣, confirmed a minute ago by
    /// the signed-in account, its payment being checked, no start tried.
    static func paidImmediate() -> LaundryCheckout {
        let draft = LaundryDraft(deviceID: device, qrCode: qr, machineName: "测试洗衣机01", program: program,
                                 request: OrderRequest(deviceID: device, deviceTypeID: 1, storeID: "test-store-01", programID: 1))
        return LaundryCheckout(phase: .verifying, draft: draft, createdAt: Date().addingTimeInterval(-60), orderID: orderID,
                               paymentRequestedAt: Date().addingTimeInterval(-50), accountID: accountID, immediate: true)
    }

    /// The live laundry and campus models as a cold launch finds them: signed in to U净 with a
    /// saved machine, and `record` stored.
    private func launchModels(record: LaundryCheckout?, ujing: ScriptedUjing,
                              inFront: @escaping @Sendable () async -> Bool) -> (CampusModel, LaundryModel) {
        let store = InMemorySecureStore()
        let vault = StoredLaundryVault(store: store)
        try! vault.saveAccountItem(UjingAccountItem(mobileID: "00000000-0000-4000-8000-000000000001",
                                                    account: UjingAccount(id: Self.accountID, userId: "1", token: "test-token")))
        try! vault.saveCheckout(record)
        let services = CampusServices(kind: .live, secureStore: store, defaults: SampleDefaults(), sharedPreferences: nil,
                                      schoolHTTP: SampleHTTPClient(), showerHTTP: SampleHTTPClient(), laundryHTTP: ujing,
                                      feedbackHTTP: nil, showerTransport: SampleShowerTransport(), leaseFile: nil,
                                      applicationSupport: nil, sharedDidChange: {})
        services.defaults.set(try! JSONEncoder().encode([SavedWasher(id: Self.device, qrCode: Self.qr, name: "楼下")]),
                              forKey: PreferenceKey.laundryMachines)
        let reminders = Reminders.sample(defaults: services.defaults)
        let campus = CampusModel(services: services, stack: services.schoolStack(), reminders: reminders) { nil }
        let laundry = LaundryModel(services: services, reminders: reminders, activities: nil, inFront: inFront)
        return (campus, laundry)
    }
}

/// Whether the app is in front, switched by the test.
private final class FrontFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// U净 for one paid order: the machine reads fail (offline); the order reads paid (20) until a
/// start was sent, then washing; the pre-start read allows a start. Counts every request by path.
private final class ScriptedUjing: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private let id = LaunchOrderReadTests.orderID

    func count(_ path: String) -> Int { lock.withLock { paths.filter { $0 == path }.count } }
    /// Every request about an order (reads, pre-start reads, starts).
    var orderRequests: [String] { lock.withLock { paths.filter { $0.contains("/orders/") } } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let path = request.url.path
        let started = lock.withLock { () -> Bool in
            paths.append(path)
            return paths.contains(UjingEndpoints.startWasher(id))
        }
        switch path {
        case UjingEndpoints.detail(id):
            return reply(order(status: started ? 40 : 20, extra: started ? #","remainTime":2400"# : ""))
        case UjingEndpoints.startCheck(id):
            return reply(order(status: 20, extra: #","moduleType":7,"online":1,"selfCleanEnable":0,"selfCleanPrice":0"#))
        case UjingEndpoints.startWasher(id):
            return reply(#"{"errorMessage":""}"#)
        default:
            throw ServiceError.offline
        }
    }

    private func order(status: Int, extra: String) -> String {
        #"{"orderId":"\#(id)","deviceId":"\#(LaunchOrderReadTests.device)","status":\#(status),"payFlag":1,"#
            + #""deviceWashModelId":1,"createAt":"2026-10-30T12:00:05+08:00","payPrice":4\#(extra)}"#
    }

    private func reply(_ data: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": "application/json"],
                     body: Data(#"{"code":0,"message":"success","data":\#(data)}"#.utf8))
    }
}
