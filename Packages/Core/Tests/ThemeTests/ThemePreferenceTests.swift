import XCTest
import Core

private final class MemoryPreferences: PreferenceStorage {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// Counts its steps; `insideLock` is true only while a step runs. `fails`: the lock can't be
/// taken (the shared container before the first unlock).
private final class SpyLock: SharedLock, @unchecked Sendable {
    var steps = 0
    var insideLock = false
    var fails = false
    func locked<T>(_ body: () throws -> T) throws -> T {
        if fails { throw CocoaError(.fileLocking) }
        steps += 1; insideLock = true
        defer { insideLock = false }
        return try body()
    }
}

/// Records whether each write happened inside the lock.
private final class LockCheckedPreferences: PreferenceStorage {
    let lock: SpyLock
    var values: [String: Any] = [:]
    var writesOutsideLock = 0
    init(lock: SpyLock) { self.lock = lock }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) {
        if !lock.insideLock { writesOutsideLock += 1 }
        values[key] = value
    }
}

/// Settings › 外观 › 主题: stored on this phone, 暖橙 until the user picks 清爽.
final class ThemePreferenceTests: XCTestCase {
    func testDefaultIsWarm() {
        XCTAssertEqual(ThemePreference(storage: MemoryPreferences()).theme, .warm)
        XCTAssertEqual(AppTheme.standard, .warm)
    }

    func testChoiceRoundTripsUnderItsOwnKey() throws {
        let storage = MemoryPreferences()
        storage.values[PreferenceKey.schoolLaundry] = false
        let preference = ThemePreference(storage: storage)
        try preference.set(.clear, under: UnsharedLock())
        XCTAssertEqual(preference.theme, .clear)
        XCTAssertEqual(ThemePreference(storage: storage).theme, .clear, "a new reader sees it")
        try preference.set(.warm, under: UnsharedLock())
        XCTAssertEqual(preference.theme, .warm)
        XCTAssertEqual(storage.values[ThemePreference.key] as? String, "warm")
        XCTAssertEqual(storage.values[PreferenceKey.schoolLaundry] as? Bool, false, "other preferences kept")
        XCTAssertEqual(ThemePreference.key, "xrc.theme")
    }

    func testUnknownOrMistypedValueIsWarm() {
        let storage = MemoryPreferences()
        storage.values[ThemePreference.key] = "classic"
        XCTAssertEqual(ThemePreference(storage: storage).theme, .warm)
        storage.values[ThemePreference.key] = ""
        XCTAssertEqual(ThemePreference(storage: storage).theme, .warm)
        storage.values[ThemePreference.key] = 1
        XCTAssertEqual(ThemePreference(storage: storage).theme, .warm)
        storage.values[ThemePreference.key] = "clear"
        XCTAssertEqual(ThemePreference(storage: storage).theme, .clear)
    }

    func testStoredThroughUserDefaults() throws {
        let suite = "ThemePreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try ThemePreference(storage: defaults).set(.clear, under: UnsharedLock())
        XCTAssertEqual(ThemePreference(storage: try XCTUnwrap(UserDefaults(suiteName: suite))).theme, .clear)
    }

    /// The choice is shared with the widget and the Live Activities: it is compared and written
    /// in one step inside the shared lock, never by a read and a separate write.
    func testWrittenInsideTheSharedLock() throws {
        let lock = SpyLock()
        let storage = LockCheckedPreferences(lock: lock)
        let preference = ThemePreference(storage: storage)
        try preference.set(.clear, under: lock)
        XCTAssertEqual(preference.theme, .clear)
        XCTAssertEqual(lock.steps, 1)
        XCTAssertEqual(storage.writesOutsideLock, 0)
        try preference.set(.clear, under: lock)
        XCTAssertEqual(lock.steps, 2, "compared inside the lock too")
        XCTAssertEqual(storage.writesOutsideLock, 0)
    }

    /// The lock can't be taken: nothing is written and the caller hears why.
    func testNothingWrittenWithoutTheLock() {
        let lock = SpyLock()
        lock.fails = true
        let storage = LockCheckedPreferences(lock: lock)
        XCTAssertThrowsError(try ThemePreference(storage: storage).set(.clear, under: lock))
        XCTAssertNil(storage.values[ThemePreference.key])
        XCTAssertEqual(ThemePreference(storage: storage).theme, .warm)
    }

    /// 主题's choice: refused while a shower or laundry run locks the theme (`ThemeLock`), whoever
    /// asks, and nothing is written or locked then; the theme already shown writes nothing either.
    func testSelectIsRefusedWhileTheThemeIsLocked() throws {
        let lock = SpyLock()
        let storage = LockCheckedPreferences(lock: lock)
        let preference = ThemePreference(storage: storage)
        for themeLock in [ThemeLock.shower, .laundry, .showerAndLaundry] {
            XCTAssertFalse(try preference.select(.clear, current: .warm, lock: themeLock, under: lock), "\(themeLock)")
        }
        XCTAssertEqual(lock.steps, 0)
        XCTAssertEqual(preference.theme, .warm)
        XCTAssertFalse(try preference.select(.warm, current: .warm, lock: nil, under: lock))
        XCTAssertEqual(lock.steps, 0)
        XCTAssertTrue(try preference.select(.clear, current: .warm, lock: nil, under: lock))
        XCTAssertEqual(preference.theme, .clear)
        XCTAssertEqual(storage.writesOutsideLock, 0)
    }

    func testSelectWithoutTheSharedLockChangesNothing() {
        let lock = SpyLock()
        lock.fails = true
        let preference = ThemePreference(storage: LockCheckedPreferences(lock: lock))
        XCTAssertThrowsError(try preference.select(.clear, current: .warm, lock: nil, under: lock))
        XCTAssertEqual(preference.theme, .warm)
    }

    /// No App Group (tests, a re-signed install without one): this process's own preferences.
    func testSharedStorageWithoutAGroupIsTheProcessOwn() {
        XCTAssertTrue(ThemePreference.sharedStorage(appGroup: nil) === UserDefaults.standard)
    }

    func testNamesAndCopy() {
        XCTAssertEqual(AppTheme.allCases, [.warm, .clear])
        XCTAssertEqual(AppTheme.warm.name, "暖橙")
        XCTAssertEqual(AppTheme.clear.name, "清爽")
        XCTAssertEqual(AppTheme.warm.settingsRowLabel, "主题，暖橙")
        XCTAssertEqual(AppTheme.clear.unavailableLabel, "清爽，暂时不能选")
        XCTAssertEqual(AppTheme.warm.summary, "暖色，数字大，一页看完。")
        XCTAssertEqual(AppTheme.clear.summary, "蓝白配色，像系统自带的 App。")
        XCTAssertEqual(AppTheme.footer, "两套的功能和数据一样，只是样子和页面排法不同。小组件、锁屏和灵动岛也会跟着换。")
    }
}
