//
//  LookPick.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/19.
//

import Foundation

/// 「选一个样子」: before a new user's first-run setup, both themes' homes side by side to pick
/// one. A new user is one `QuickSetupSeen.isFirstRun` says is; someone upgrading has set
/// something up or seen the setup, so never sees it. Picked once, kept in the app's
/// preferences under `key`; 重置校日常 clears them, so it is asked again after a reset.
public enum LookPick {
    public static let key = PreferenceKey.prefix + "pickedLook"

    /// Shown now: a new user (`firstRun`) who has not picked a look yet.
    public static func isDue(firstRun: Bool, in storage: PreferenceStorage) -> Bool {
        firstRun && !hasPicked(in: storage)
    }

    public static func hasPicked(in storage: PreferenceStorage) -> Bool {
        storage.object(forKey: key) as? Bool == true
    }

    /// 「用暖橙」/「用清爽」 was tapped: not asked again.
    public static func picked(in storage: PreferenceStorage) {
        storage.set(true, forKey: key)
    }
}
