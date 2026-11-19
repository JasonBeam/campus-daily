import XCTest
import Core
import CoreTestSupport

/// Counts every write; reads see what was written.
private final class SpyPreferences: PreferenceStorage {
    var values: [String: Any] = [:]
    var writes = 0
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { writes += 1; values[key] = value }
}

/// A Keychain that counts writes and deletes.
private final class SpyKeychain: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [StoreKey: Data] = [:]
    private(set) var writes = 0
    private(set) var deletes = 0
    func read(_ key: StoreKey) throws -> Data? { lock.withLock { items[key] } }
    func write(_ data: Data, for key: StoreKey) throws { lock.withLock { writes += 1; items[key] = data } }
    func delete(_ key: StoreKey) throws { lock.withLock { deletes += 1; items[key] = nil } }
}

private struct PlainLock: SharedLock {
    func locked<T>(_ body: () throws -> T) throws -> T { try body() }
}

/// Stands in for the real services an action would call: the school's top-up, the shower
/// engine, U净, the feedback sender, the reset. Each call would send a request.
@MainActor private final class SpyService {
    var calls: [SampleAction] = []
    let store: SpyKeychain
    let preferences: SpyPreferences
    init(store: SpyKeychain, preferences: SpyPreferences) { self.store = store; self.preferences = preferences }

    /// What the real action does: a request, then what it stores.
    func run(_ action: SampleAction) {
        calls.append(action)
        try? store.write(Data(action.rawValue.utf8), for: .laundryCheckout)
        preferences.set(action.rawValue, forKey: "last-" + action.rawValue)
    }

    func runAsync(_ action: SampleAction) async {
        await Task.yield()
        run(action)
    }
}

@MainActor
final class SampleModeTests: XCTestCase {
    private var preferences: SpyPreferences!
    private var shared: SpyPreferences!
    private var keychain: SpyKeychain!
    private var service: SpyService!

    override func setUp() async throws {
        preferences = SpyPreferences()
        shared = SpyPreferences()
        keychain = SpyKeychain()
        service = SpyService(store: keychain, preferences: preferences)
    }

    /// Everything a reviewer can do in the sample: pick 清爽 and back, try every blocked action,
    /// close the first-run guide, leave. Nothing real is called and nothing live is written: the
    /// theme and the 「seen」 flag land in the sample's own preferences.
    func testEnteringAndLeavingWritesNothing() async throws {
        let sample = SampleMode.overIdleShower()
        let liveTheme = ThemePreference(storage: shared)
        sample.enter()
        let services = try XCTUnwrap(sample.services)
        // The first-run guide closes as the sample opens: its 「seen」 flag is not stored.
        QuickSetupSeen.closed(in: preferences, coveredBySample: sample.isActive)
        let theme = ThemePreference(storage: try XCTUnwrap(services.sharedPreferences))
        XCTAssertTrue(try theme.select(.clear, current: .warm, lock: nil, under: PlainLock()))
        XCTAssertEqual(theme.theme, .clear)
        for action in SampleAction.allCases {
            XCTAssertFalse(sample.perform(action) { service.run(action) })
            XCTAssertEqual(sample.blocked, action)
            sample.blocked = nil
            let ran = await sample.perform(action) { await service.runAsync(action) }
            XCTAssertFalse(ran)
        }
        XCTAssertTrue(try theme.select(.warm, current: .clear, lock: nil, under: PlainLock()))
        sample.leave()

        XCTAssertFalse(sample.isActive)
        XCTAssertNil(sample.services)
        XCTAssertNil(sample.blocked)
        XCTAssertEqual(service.calls, [])
        XCTAssertEqual(preferences.writes, 0)
        XCTAssertEqual(shared.writes, 0)
        XCTAssertEqual(keychain.writes, 0)
        XCTAssertEqual(keychain.deletes, 0)
        XCTAssertEqual(liveTheme.theme, .warm)
    }

    /// The theme picked in the sample is gone with it: the stored one shows again, and the next
    /// sample starts on the default.
    func testThemeIsHeldOnlyWhileInTheSample() throws {
        let sample = SampleMode.overIdleShower()
        let live = ThemePreference(storage: shared)
        sample.enter()
        let theme = ThemePreference(storage: try XCTUnwrap(sample.services?.sharedPreferences))
        _ = try theme.select(.clear, current: .warm, lock: nil, under: PlainLock())
        XCTAssertEqual(theme.theme, .clear)
        sample.leave()
        sample.enter()
        XCTAssertEqual(ThemePreference(storage: try XCTUnwrap(sample.services?.sharedPreferences)).theme, .warm)
        XCTAssertEqual(live.theme, .warm)
        XCTAssertEqual(shared.writes, 0)
    }

    /// Money paths in the sample never reach the service; outside it they do (control).
    func testMoneyActionsReachTheServiceOnlyOutsideTheSample() async {
        let money: [SampleAction] = [.cardRecharge, .powerRecharge, .startShower, .startWash, .payLaundry]
        let sample = SampleMode.overIdleShower()
        sample.enter()
        for action in money {
            sample.perform(action) { service.run(action) }
            await sample.perform(action) { await service.runAsync(action) }
        }
        XCTAssertEqual(service.calls, [])
        sample.leave()

        for action in money {
            XCTAssertTrue(sample.perform(action) { service.run(action) })
        }
        XCTAssertEqual(service.calls, money)
        XCTAssertNil(sample.blocked)
        let ran = await sample.perform(.startWash) { await service.runAsync(.startWash) }
        XCTAssertTrue(ran)
        XCTAssertEqual(service.calls.count, money.count + 1)
    }

    /// Outside the sample, writes and the theme choice go through as before.
    func testOutsideTheSampleEverythingIsStored() throws {
        let sample = SampleMode.overIdleShower()
        let theme = ThemePreference(storage: shared)
        QuickSetupSeen.closed(in: preferences, coveredBySample: sample.isActive)
        XCTAssertEqual(preferences.writes, 1)
        XCTAssertTrue(try theme.select(.clear, current: .warm, lock: nil, under: PlainLock()))
        XCTAssertEqual(theme.theme, .clear)
        XCTAssertNil(sample.services)
    }

    /// The sample is not kept: a new launch (a new instance) starts outside it, and entering
    /// it stores nowhere a later launch could read it from.
    func testSampleIsNotPersisted() {
        let first = SampleMode.overIdleShower()
        first.enter()
        XCTAssertTrue(first.isActive)
        XCTAssertEqual(preferences.writes + shared.writes + keychain.writes, 0)
        let relaunched = SampleMode.overIdleShower()
        XCTAssertFalse(relaunched.isActive)
        XCTAssertNil(relaunched.services)
    }

    /// A theme lock (a run going on) still holds in the sample.
    func testLockedThemeDoesNotChangeInTheSample() throws {
        let sample = SampleMode.overIdleShower()
        sample.enter()
        let theme = ThemePreference(storage: try XCTUnwrap(sample.services?.sharedPreferences))
        XCTAssertFalse(try theme.select(.clear, current: .warm, lock: .shower, under: PlainLock()))
        XCTAssertEqual(theme.theme, .warm)
        XCTAssertFalse(try theme.select(.warm, current: .warm, lock: nil, under: PlainLock()))
    }

    /// 去登录 opens the login step once, on whichever root shows next; a launch has none due.
    func testLeavingOpensTheLoginOnce() {
        let sample = SampleMode.overIdleShower()
        XCTAssertFalse(sample.takeLogin())
        sample.enter()
        XCTAssertFalse(sample.loginDue)
        sample.leave()
        XCTAssertTrue(sample.loginDue)
        XCTAssertTrue(sample.takeLogin())
        XCTAssertFalse(sample.takeLogin())
        sample.enter()
        sample.leave()
        sample.enter()
        XCTAssertFalse(sample.takeLogin())
    }

    /// Leaving with a link kept from the sample has one destination, that link: no login step,
    /// and the automatic first-run setup stays shut (also on a root built after the link was
    /// taken). Without a kept link, the login step as before.
    func testLeavingWithAKeptLinkGoesOnlyThere() throws {
        let sample = SampleMode.overIdleShower()
        sample.enter()
        XCTAssertEqual(sample.open(try XCTUnwrap(URL(string: "campusdaily://login"))), .held)
        XCTAssertEqual(sample.open(try XCTUnwrap(URL(string: "campusdaily://home"))), .held)
        sample.leave()
        XCTAssertFalse(sample.loginDue, "the kept link is where it goes")
        XCTAssertTrue(sample.firstRunHeld)
        XCTAssertFalse(sample.takeLogin())
        XCTAssertEqual(sample.takePendingLink(), .home)
        XCTAssertTrue(sample.firstRunHeld, "still held once the link is taken")

        sample.enter()
        XCTAssertFalse(sample.firstRunHeld)
        sample.leave()
        XCTAssertTrue(sample.loginDue, "no kept link: the login step")
        XCTAssertFalse(sample.firstRunHeld)
    }

    func testCopy() {
        XCTAssertEqual(SampleCopy.entry, "先看看示例")
        XCTAssertEqual(SampleCopy.entryRefused, "有一次洗澡还没结完，结完就能看示例。")
        XCTAssertEqual(SampleCopy.entryUnavailable, "不可用")
        XCTAssertEqual(SampleCopy.barText, "示例数据，不是你的账号")
        XCTAssertEqual(SampleCopy.barAction, "去登录")
        XCTAssertEqual(SampleCopy.barSpoken, "示例数据，不是你的账号。去登录")
        XCTAssertEqual(SampleCopy.blocked, "示例里不能操作，登录学校账号后就能用。")
    }
}
