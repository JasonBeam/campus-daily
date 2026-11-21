//
//  ShowerStartOverrideStoreTests.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import XCTest
@testable import Core

/// Whether a start below zero is allowed on this phone: one Keychain item that never leaves the
/// device, kept across relaunches and sign-outs, cleared by 重置校日常.
final class ShowerStartOverrideStoreTests: XCTestCase {
    func testOffByDefault() {
        XCTAssertFalse(ShowerStartOverrideStore(store: InMemorySecureStore()).isOn)
    }

    /// On, then a new store over the same Keychain (a relaunch) reads it on; off again reads off.
    func testItIsKeptAcrossARelaunch() throws {
        let keychain = InMemorySecureStore()
        try ShowerStartOverrideStore(store: keychain).set(true)
        XCTAssertTrue(ShowerStartOverrideStore(store: keychain).isOn)
        try ShowerStartOverrideStore(store: keychain).set(false)
        XCTAssertFalse(ShowerStartOverrideStore(store: keychain).isOn)
    }

    /// Its own Keychain item, in the app's private group, readable only on this device.
    func testItIsADeviceOnlyKeychainItem() throws {
        let keychain = InMemorySecureStore()
        try ShowerStartOverrideStore(store: keychain).set(true)
        XCTAssertNotNil(try keychain.read(.showerStartMode))
        XCTAssertTrue(StoreKey.showerStartMode.accessibility.rawValue.hasSuffix("ThisDeviceOnly"))
        XCTAssertFalse(StoreKey.showerStartMode.isShared, "not the widget's")
    }

    func testResetClearsIt() throws {
        let keychain = InMemorySecureStore()
        try ShowerStartOverrideStore(store: keychain).set(true)
        XCTAssertTrue(ShowerStartOverrideStore(store: keychain).isOn)
        let defaults = UserDefaults(suiteName: "override-reset-\(UUID().uuidString)")!
        try AppReset.clear(store: keychain, preferences: defaults, preferencesDomain: "override-reset", shared: nil, files: [])
        XCTAssertFalse(ShowerStartOverrideStore(store: keychain).isOn)
        XCTAssertTrue(AppReset.keychainItems.contains(.showerStartMode))
    }

    /// Something unreadable is off, never on.
    func testGarbageIsOff() throws {
        let keychain = InMemorySecureStore()
        try keychain.write(Data("garbage".utf8), for: .showerStartMode)
        XCTAssertFalse(ShowerStartOverrideStore(store: keychain).isOn)
    }
}
