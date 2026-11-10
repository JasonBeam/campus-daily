import XCTest
import Core
import CoreTestSupport

/// The live app's stores and services, every touch counted. `trap`: any touch also fails the test.
private final class LiveSpies: @unchecked Sendable {
    let lock = NSLock()
    let trap: Bool
    private(set) var touches: [String] = []
    init(trap: Bool = false) { self.trap = trap }
    func touch(_ what: String) {
        lock.withLock { touches.append(what) }
        if trap { XCTFail("the sample reached the live \(what)") }
    }
    var count: Int { lock.withLock { touches.count } }
}

private final class SpyStore: SecureStore, @unchecked Sendable {
    let spies: LiveSpies
    let inner = InMemorySecureStore()
    var counting = true
    init(_ spies: LiveSpies) { self.spies = spies }
    func read(_ key: StoreKey) throws -> Data? { if counting { spies.touch("keychain read") }; return try inner.read(key) }
    func write(_ data: Data, for key: StoreKey) throws { if counting { spies.touch("keychain write") }; try inner.write(data, for: key) }
    func delete(_ key: StoreKey) throws { if counting { spies.touch("keychain delete") }; try inner.delete(key) }
}

private final class SpyDefaults: UserDefaults {
    var spies: LiveSpies!
    convenience init(_ spies: LiveSpies) { self.init(suiteName: "spy.\(UUID().uuidString)")!; self.spies = spies }
    override func object(forKey key: String) -> Any? { spies.touch("defaults read"); return nil }
    override func set(_ value: Any?, forKey key: String) { spies.touch("defaults write") }
    override func bool(forKey key: String) -> Bool { spies.touch("defaults read"); return false }
}

private final class SpyPreferences: PreferenceStorage {
    let spies: LiveSpies
    init(_ spies: LiveSpies) { self.spies = spies }
    func object(forKey key: String) -> Any? { spies.touch("shared read"); return nil }
    func set(_ value: Any?, forKey key: String) { spies.touch("shared write") }
}

private struct SpyHTTP: HTTPClient {
    let spies: LiveSpies
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { spies.touch("request"); throw ServiceError.timedOut }
}

private struct SpyTransport: ShowerTransport {
    let spies: LiveSpies
    func connect(bleName: String, machineID: String, required: String?, preferred: String?) async throws -> String {
        spies.touch("bluetooth connect"); return "PERIPHERAL-A"
    }
    func exchange(_ command: Data) async throws -> Data { spies.touch("bluetooth write"); throw ShowerDeviceError.timedOut }
    func disconnect() async { spies.touch("bluetooth disconnect") }
}

private func liveServices(_ spies: LiveSpies, store: SpyStore) -> CampusServices {
    CampusServices(kind: .live, secureStore: store, defaults: SpyDefaults(spies), sharedPreferences: SpyPreferences(spies),
                   schoolHTTP: SpyHTTP(spies: spies), showerHTTP: SpyHTTP(spies: spies), laundryHTTP: SpyHTTP(spies: spies),
                   feedbackHTTP: SpyHTTP(spies: spies), showerTransport: SpyTransport(spies: spies), leaseFile: nil,
                   applicationSupport: nil, sharedDidChange: { spies.touch("widget reload") })
}

private let binding = ShowerBinding(studentId: "S-1", schoolId: "1", machineId: "AABBCC", roomId: "R-1", roomLabel: "3栋108")
private let profile = ShowerPlatformProfile(secret: "synthetic", sid: "synthetic", bleName: "SYNTHETIC", typeId: "0", version: "1")

/// 「先看看示例」 runs on its own services (`SampleMode.services(live:)`): the live session,
/// Keychain, preferences, network and Bluetooth are neither visible nor reachable from it.
@MainActor
final class SampleIsolationTests: XCTestCase {
    /// A real shower is running (its record in the live Keychain). Entered into the sample, the
    /// hot-water engine the app builds on the scene's services sees no session, and every shower
    /// action (start, cancel, end and settle, check, settle retry, resolve, clear) reaches nothing
    /// live. Left, the real record is as it was.
    func testShowerActionsInTheSampleNeverReachTheRealSession() async throws {
        let spies = LiveSpies()
        let store = SpyStore(spies)
        let live = liveServices(spies, store: store)
        let running = ShowerState(phase: .running, machineID: binding.machineId, peripheralID: "PERIPHERAL-A",
                                  startedAt: Date().addingTimeInterval(-300))
        store.counting = false
        try live.showerVault.saveBinding(binding)
        try live.showerVault.saveShowerState(running)
        store.counting = true

        let sample = SampleMode.overIdleShower()
        sample.enter()
        let services = sample.services(live: live)
        XCTAssertNil(try services.showerVault.showerState(), "the real session shows in the sample")
        XCTAssertNil(try services.showerVault.binding())
        let engine = try services.showerEngine(gateway: services.showerGateway(profile: profile), bleName: profile.bleName)
        let shown = await engine.state
        XCTAssertEqual(shown.phase, .idle)
        _ = try? await engine.start(binding)
        _ = await engine.cancelStart()
        _ = try? await engine.finish(binding)
        _ = try? await engine.review(binding)
        _ = try? await engine.requestSettleRetry()
        _ = try? await engine.confirmSettleRetry(binding)
        _ = try? await engine.disarmSettleRetry()
        _ = try? await engine.resolveManually()
        _ = try? await engine.dismiss()
        sample.leave()

        XCTAssertEqual(spies.touches, [])
        XCTAssertTrue(sample.services(live: live) === live)
        store.counting = false
        XCTAssertEqual(try live.showerVault.showerState(), running)
        XCTAssertEqual(try live.showerVault.binding(), binding)
    }

    /// The sample's services are built from nothing live: with live services that fail the test
    /// on any touch, a sample uses its Keychain, preferences, App Group, every client, Bluetooth,
    /// the school refresh and the hot-water engine without one.
    func testTheSampleHoldsNoLiveStoreOrService() async throws {
        let spies = LiveSpies(trap: true)
        let live = liveServices(spies, store: SpyStore(spies))
        let sample = SampleMode.overIdleShower()
        sample.enter()
        let services = sample.services(live: live)
        XCTAssertFalse(services === live)
        XCTAssertEqual(services.kind, .sample)

        try services.secureStore.write(Data("x".utf8), for: .laundryCheckout)
        _ = try services.secureStore.read(.schoolPassword)
        services.defaults.set(true, forKey: QuickSetupSeen.key)
        XCTAssertTrue(services.defaults.bool(forKey: QuickSetupSeen.key))
        let theme = try XCTUnwrap(services.sharedPreferences)
        XCTAssertTrue(try ThemePreference(storage: theme).select(.clear, current: .warm, lock: nil, under: UnsharedLock()))
        for http in [services.schoolHTTP, services.showerHTTP, services.laundryHTTP] + [services.feedbackHTTP].compactMap({ $0 }) {
            let request = HTTPRequest(service: .cas, method: .get, url: URL(string: "https://example.invalid/")!)
            do { _ = try await http.send(request); XCTFail("a sample request went out") } catch {}
        }
        do { _ = try await services.showerTransport.connect(bleName: "X", machineID: "AABBCC", required: nil, preferred: nil); XCTFail() } catch {}
        let report = await services.schoolStack().refresher.refresh(inBackground: false)
        XCTAssertEqual(report.outcome, .notSignedIn)
        let engine = try services.showerEngine(gateway: services.showerGateway(profile: profile), bleName: "X")
        _ = try? await engine.start(binding)
        _ = try? await engine.finish(binding)
        services.sharedDidChange()
        sample.leave()
        XCTAssertEqual(spies.count, 0)
    }

    /// Each sample starts empty: what one stored (a theme, a seen flag) is gone with it.
    func testEachSampleStartsOnNewServices() throws {
        let sample = SampleMode.overIdleShower()
        sample.enter()
        let first = try XCTUnwrap(sample.services)
        first.defaults.set(true, forKey: QuickSetupSeen.key)
        sample.leave()
        XCTAssertNil(sample.services)
        sample.enter()
        let second = try XCTUnwrap(sample.services)
        XCTAssertFalse(first === second)
        XCTAssertFalse(second.defaults.bool(forKey: QuickSetupSeen.key))
        XCTAssertNil(UserDefaults.standard.object(forKey: QuickSetupSeen.key + ".sample-probe"))
    }

    /// The sample's preferences live in memory: the typed reads `@AppStorage` uses see what was
    /// set, registered values show through, and no other UserDefaults sees any of it.
    func testSampleDefaultsKeepEverythingInMemory() {
        let defaults = SampleDefaults()
        let key = "xrc.sample-probe.\(UUID().uuidString)"
        defaults.register(defaults: [key + ".line": 10])
        XCTAssertEqual(defaults.integer(forKey: key + ".line"), 10)
        defaults.set(20, forKey: key + ".line")
        defaults.set(true, forKey: key)
        defaults.set("3", forKey: key + ".text")
        XCTAssertEqual(defaults.integer(forKey: key + ".line"), 20)
        XCTAssertTrue(defaults.bool(forKey: key))
        XCTAssertEqual(defaults.string(forKey: key + ".text"), "3")
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
        XCTAssertFalse(SampleDefaults().bool(forKey: key))
        defaults.removeObject(forKey: key)
        XCTAssertFalse(defaults.bool(forKey: key))
    }

    /// The widget's and the login links in the sample: it stays on screen and nothing opens; the
    /// latest one is kept and the live root gets it once after the sample is left, by any way out.
    func testLiveLinksWaitForTheSampleToBeLeft() throws {
        let ways: [@MainActor (SampleMode) -> Void] = [{ $0.leave() }, { $0.leaveForLive() }]
        for leave in ways {
            for (text, link) in [("campusdaily://login", RootLink.login), ("campusdaily://settings/account", .settings(account: true)),
                                 ("campusdaily://home", .home), ("campusdaily://settings", .settings(account: false))] {
                let sample = SampleMode.overIdleShower()
                sample.enter()
                let services = sample.services
                XCTAssertEqual(sample.open(URL(string: "campusdaily://home")!), .held)
                XCTAssertEqual(sample.open(URL(string: text)!), .held, text)
                XCTAssertTrue(sample.isActive, text)
                XCTAssertTrue(sample.services === services, "the sample is not built again (\(text))")
                XCTAssertNil(sample.takePendingLink(), text)
                leave(sample)
                XCTAssertEqual(sample.takePendingLink(), link, "the latest only (\(text))")
                XCTAssertNil(sample.takePendingLink(), text)
            }
        }
    }

    /// Other campusdaily links leave the sample on screen and open nothing, now or later;
    /// another app's answer (Alipay) waits for the live app; outside the sample every link is the
    /// live app's.
    func testOtherLinksInTheSample() throws {
        let sample = SampleMode.overIdleShower()
        XCTAssertEqual(sample.open(URL(string: "campusdaily://login")!), .live)
        XCTAssertEqual(sample.takePendingLink(), .login)
        sample.enter()
        XCTAssertEqual(sample.open(URL(string: "campusdaily://demo/shower")!), .ignored)
        XCTAssertEqual(sample.open(URL(string: "campusdaily://nothing")!), .ignored)
        let alipay = URL(string: "xiaorichang-alipay://safepay/?result=synthetic")!
        XCTAssertEqual(sample.open(alipay), .held)
        XCTAssertTrue(sample.isActive)
        XCTAssertNil(sample.takePendingLink())
        XCTAssertEqual(sample.takeHeldLinks(), [])
        sample.leave()
        XCTAssertNil(sample.takePendingLink())
        XCTAssertEqual(sample.takeHeldLinks(), [alipay])
        XCTAssertEqual(sample.takeHeldLinks(), [])
    }

    /// 清爽's checklist (and 暖橙's guide) closed because the sample opened over it: the live
    /// 「seen」 flag is not written, so leaving finds the first-run setup as before. Closed by the
    /// user outside the sample, it is.
    func testSetupClosedByTheSampleIsNotSeen() {
        let spies = LiveSpies()
        let live = SpyPreferences(spies)
        let sample = SampleMode.overIdleShower()
        sample.enter()
        QuickSetupSeen.closed(in: live, coveredBySample: sample.isActive)
        XCTAssertEqual(spies.count, 0)
        sample.leave()
        QuickSetupSeen.closed(in: live, coveredBySample: sample.isActive)
        XCTAssertEqual(spies.touches, ["shared write"])
    }

    /// A reminder prompt queued on the live home (first home read) before the sample opened:
    /// in the sample it is neither shown nor taken nor marked shown; after it, it shows once.
    func testQueuedReminderPromptWaitsForTheLiveApp() {
        let spies = LiveSpies()
        let sample = SampleMode.overIdleShower()
        let queue = ReminderPromptQueue(storage: SpyPreferences(spies), promptedKey: "xrc.reminder.prompted",
                                        held: { [weak sample] in sample?.isActive ?? false })
        queue.request(notDetermined: true)
        XCTAssertTrue(queue.pending)
        let reads = spies.count
        sample.enter()
        XCTAssertFalse(queue.take(notDetermined: true, showing: false))
        XCTAssertTrue(queue.pending)
        XCTAssertEqual(spies.touches.dropFirst(reads).filter { $0.hasSuffix("write") }, [])
        sample.leave()
        XCTAssertTrue(queue.take(notDetermined: true, showing: false))
        XCTAssertFalse(queue.pending)
        XCTAssertEqual(spies.touches.filter { $0.hasSuffix("write") }, ["shared write"])
    }
}
