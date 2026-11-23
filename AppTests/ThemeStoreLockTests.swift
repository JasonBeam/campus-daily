//
//  ThemeStoreLockTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/23.
//

import XCTest
import Core
@testable import XiaoRiChang

/// 主题 with the shared lock held elsewhere (the widget's step, or one stuck there): picking a
/// theme never waits for it on the main thread; the choice is stored and shown once the lock is
/// free, and a newer choice replaces one still waiting.
@MainActor
final class ThemeStoreLockTests: XCTestCase {
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("theme-lock-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at:url)
        super.tearDown()
    }

    /// Another descriptor holding the lease file's exclusive lock.
    private func holdLock() throws -> Int32 {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileLocking) }
        return fd
    }

    private func unlock(_ fd: Int32) { flock(fd, LOCK_UN); close(fd) }

    private func store(_ defaults: SampleDefaults) -> ThemeStore {
        let lock = RefreshLease(file:LeaseFile(url:url), owner:"app-test")
        return ThemeStore(preference:ThemePreference(storage:defaults), lock:lock, didChange:{}) { nil }
    }

    func testSelectNeverWaitsOnAHeldLock() async throws {
        let defaults = SampleDefaults()
        let theme = store(defaults)
        let fd = try holdLock()

        let started = Date()
        theme.select(.clear)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.1, "the main thread did not wait for the lock")
        XCTAssertEqual(theme.theme, .warm, "not shown before it is stored")
        XCTAssertEqual(ThemePreference(storage:defaults).theme, .warm, "nothing written without the lock")

        unlock(fd)
        await theme.settled()
        XCTAssertEqual(theme.theme, .clear, "stored and shown once the lock is free")
        XCTAssertEqual(ThemePreference(storage:defaults).theme, .clear)
    }

    func testANewerChoiceReplacesOneStillWaiting() async throws {
        let defaults = SampleDefaults()
        let theme = store(defaults)
        let fd = try holdLock()
        theme.select(.clear)
        unlock(fd)
        theme.select(.clear)
        await theme.settled()
        XCTAssertEqual(theme.theme, .clear)

        let again = try holdLock()
        theme.select(.warm)
        unlock(again)
        theme.select(.clear)
        await theme.settled()
        XCTAssertEqual(theme.theme, .clear, "the waiting 暖橙 was dropped for the newer choice")
        XCTAssertEqual(ThemePreference(storage:defaults).theme, .clear)
    }

    func testAFreeLockStoresAtOnce() {
        let defaults = SampleDefaults()
        let theme = store(defaults)
        theme.select(.clear)
        XCTAssertEqual(theme.theme, .clear)
        XCTAssertEqual(ThemePreference(storage:defaults).theme, .clear)
    }
}
