//
//  ShowerVault.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/01.
//

import Foundation

/// Hot-water persistence (Keychain `water.binding`, `water.session`). Session writes fail
/// closed: the engine runs no side effect after a failed write.
public protocol ShowerVault: Sendable {
    func binding() throws -> ShowerBinding?
    func saveBinding(_ binding: ShowerBinding?) throws
    func showerState() throws -> ShowerState?
    func saveShowerState(_ state: ShowerState?) throws
    /// Records kept by a next use while they wait for the user's check, oldest first. They are
    /// only shown: nothing ends, checks or settles a kept record.
    func retainedShowers() throws -> [ShowerState]
    /// The kept records of the student the saved binding names, oldest first: the ones the
    /// pages show. Another student's stay stored and are not returned; none without a binding.
    func retainedShowersForBinding() throws -> [ShowerState]
    /// Keeps `state` as it is (adds it once). Throws when it can't be kept for sure.
    func retainShower(_ state: ShowerState) throws
}

extension ShowerVault {
    public func retainedShowers() throws -> [ShowerState] { [] }
    public func retainedShowersForBinding() throws -> [ShowerState] { [] }
    /// A vault that can't keep records refuses: the next use never goes ahead without it.
    public func retainShower(_ state: ShowerState) throws { throw ShowerEngineError.storage }
}

extension ShowerVault {
    /// The way out of a saved record that can't be decoded, once the user checked the school's
    /// record: it is removed only while it still can't be read. True when it was removed; false
    /// when there is no record or it reads (then it is kept). A Keychain error is thrown.
    public func clearUnreadableRecord() throws -> Bool {
        do {
            _ = try showerState()
            return false
        } catch ShowerEngineError.unreadableRecord {
            try saveShowerState(nil)
            return true
        }
    }
}
